package com.nurtrino.hackernews.ui

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.List
import androidx.compose.material.icons.filled.Menu
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.ExitToApp
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
import com.nurtrino.hackernews.data.LobstersViewModel
import com.nurtrino.hackernews.data.Settings
import com.nurtrino.hackernews.data.StoryTapAction
import com.nurtrino.hackernews.model.LoadPhase
import com.nurtrino.hackernews.model.LobstersFeed
import com.nurtrino.hackernews.model.LobstersStory

/** The Lobsters tab: a feed switcher plus the selected lobste.rs story list. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LobstersScreen(
    lobsters: LobstersViewModel,
    settings: Settings,
    library: Library,
    onOpenStory: (String) -> Unit,
) {
    val context = LocalContext.current
    val feed = lobsters.selectedFeed
    val state = lobsters.state(feed)
    var menuOpen by remember { mutableStateOf(false) }

    LaunchedEffect(feed) { lobsters.loadIfNeeded(feed) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(feed.longTitle) },
                navigationIcon = {
                    IconButton(onClick = { menuOpen = true }) {
                        Icon(Icons.Filled.Menu, contentDescription = "Choose feed")
                    }
                    DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                        LobstersFeed.entries.forEach { candidate ->
                            DropdownMenuItem(
                                text = { Text(candidate.title) },
                                onClick = {
                                    menuOpen = false
                                    lobsters.selectedFeed = candidate
                                },
                            )
                        }
                    }
                },
                actions = {
                    IconButton(onClick = { openLink(context, feed.webUrl, settings.linkTarget) }) {
                        Icon(Icons.Filled.ExitToApp, contentDescription = "Open on Lobsters")
                    }
                    IconButton(onClick = { lobsters.refresh(feed) }) {
                        Icon(Icons.Filled.Refresh, contentDescription = "Refresh")
                    }
                },
            )
        },
    ) { padding ->
        val phase = state.phase
        when {
            state.items.isEmpty() && phase == LoadPhase.Loading ->
                LoadingState("Loading ${feed.title.lowercase()} stories…")

            state.items.isEmpty() && phase is LoadPhase.Failed ->
                EmptyState(
                    icon = Icons.Filled.Warning,
                    title = "Something went wrong",
                    message = phase.message,
                    actionLabel = "Try Again",
                    onAction = { lobsters.refresh(feed) },
                )

            state.items.isEmpty() && phase == LoadPhase.Loaded ->
                EmptyState(
                    icon = Icons.Filled.Info,
                    title = "Nothing here yet",
                    message = "This feed came back empty.",
                    actionLabel = "Refresh",
                    onAction = { lobsters.refresh(feed) },
                )

            else -> LazyColumn(modifier = Modifier.padding(padding)) {
                items(count = state.items.size) { index ->
                    val story = state.items[index]
                    LobstersStoryRow(
                        story = story,
                        settings = settings,
                        library = library,
                        onClick = {
                            if (settings.markStoriesRead) library.markRead(story.numericId)
                            when (settings.storyTap) {
                                StoryTapAction.COMMENTS -> onOpenStory(story.shortId)
                                StoryTapAction.LINK ->
                                    openLink(context, story.primaryUrl, settings.linkTarget)
                            }
                        },
                    )
                    HorizontalDivider()
                }
                if (state.canLoadMore) {
                    item { LoadMoreRow { lobsters.loadMore(feed) } }
                }
            }
        }
    }
}

/** One lobste.rs story in a list, with a long-press menu. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun LobstersStoryRow(
    story: LobstersStory,
    settings: Settings,
    library: Library,
    onClick: () -> Unit,
) {
    val context = LocalContext.current
    var menuOpen by remember { mutableStateOf(false) }
    val isRead = library.isRead(story.numericId)

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .combinedClickable(onClick = onClick, onLongClick = { menuOpen = true })
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.Top,
    ) {
        if (settings.showSourceBadges) {
            Row(modifier = Modifier.padding(end = 11.dp)) {
                SourceBadge(story.sourceLabel, story.host ?: "lobsters")
            }
        }

        Column(modifier = Modifier.fillMaxWidth()) {
            Text(
                story.title,
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.SemiBold,
                color = if (isRead && settings.dimReadStories) {
                    MaterialTheme.colorScheme.onSurfaceVariant
                } else {
                    MaterialTheme.colorScheme.onSurface
                },
                maxLines = 4,
            )

            story.host?.let { host ->
                Text(
                    host,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.primary,
                    maxLines = 1,
                    modifier = Modifier.padding(top = 4.dp),
                )
            }

            if (story.tags.isNotEmpty()) {
                LobstersTagRow(story.tags, modifier = Modifier.padding(top = 6.dp))
            }

            Row(
                modifier = Modifier.padding(top = 6.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                MetaLabel(Icons.Filled.KeyboardArrowUp, abbreviated(story.score))
                MetaLabel(Icons.Filled.List, abbreviated(story.commentCount))
                story.submitter?.let { MetaLabel(Icons.Filled.Person, it) }
                MetaLabel(Icons.Filled.DateRange, shortAge(story.createdAt))
            }
        }
    }

    DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
        story.link?.let { link ->
            DropdownMenuItem(
                text = { Text("Open Article") },
                onClick = {
                    menuOpen = false
                    openLink(context, link, settings.linkTarget)
                },
            )
        }
        DropdownMenuItem(
            text = { Text("Open on Lobsters") },
            onClick = {
                menuOpen = false
                openLink(context, story.lobstersUrl, settings.linkTarget)
            },
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
        DropdownMenuItem(
            text = { Text("Copy Link") },
            onClick = {
                menuOpen = false
                copyToClipboard(context, story.primaryUrl)
            },
        )
    }
}

/** Lobsters' tags as small coloured chips. Only the first few fit on a row. */
@Composable
fun LobstersTagRow(tags: List<String>, modifier: Modifier = Modifier) {
    Row(
        modifier = modifier,
        horizontalArrangement = Arrangement.spacedBy(5.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        tags.take(5).forEach { tag ->
            val color = stableColor(tag)
            Text(
                tag,
                style = MaterialTheme.typography.labelSmall,
                color = color,
                maxLines = 1,
                modifier = Modifier
                    .background(color.copy(alpha = 0.14f), RoundedCornerShape(50))
                    .padding(horizontal = 7.dp, vertical = 2.dp),
            )
        }
        if (tags.size > 5) {
            Text(
                "+${tags.size - 5}",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

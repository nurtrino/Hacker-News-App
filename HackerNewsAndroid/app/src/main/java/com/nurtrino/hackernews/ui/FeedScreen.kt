package com.nurtrino.hackernews.ui

import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Menu
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import com.nurtrino.hackernews.data.FeedsViewModel
import com.nurtrino.hackernews.data.Library
import com.nurtrino.hackernews.data.Settings
import com.nurtrino.hackernews.data.StoryTapAction
import com.nurtrino.hackernews.model.Feed
import com.nurtrino.hackernews.model.LoadPhase

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FeedScreen(
    feeds: FeedsViewModel,
    settings: Settings,
    library: Library,
    onOpenStory: (Int) -> Unit,
) {
    val context = LocalContext.current
    var selected by remember { mutableStateOf<Feed?>(null) }
    val feed = selected ?: settings.defaultFeed
    val state = feeds.state(feed)
    var menuOpen by remember { mutableStateOf(false) }

    LaunchedEffect(feed) { feeds.loadIfNeeded(feed) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(feed.longTitle) },
                navigationIcon = {
                    IconButton(onClick = { menuOpen = true }) {
                        Icon(Icons.Filled.Menu, contentDescription = "Choose feed")
                    }
                    DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                        Feed.entries.forEach { candidate ->
                            DropdownMenuItem(
                                text = { Text(candidate.title) },
                                onClick = {
                                    menuOpen = false
                                    selected = candidate
                                },
                            )
                        }
                    }
                },
                actions = {
                    IconButton(onClick = { feeds.refresh(feed) }) {
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
                    onAction = { feeds.refresh(feed) },
                )

            state.items.isEmpty() && phase == LoadPhase.Loaded ->
                EmptyState(
                    icon = Icons.Filled.Info,
                    title = "Nothing here yet",
                    message = "This feed came back empty.",
                    actionLabel = "Refresh",
                    onAction = { feeds.refresh(feed) },
                )

            else -> LazyColumn(modifier = Modifier.padding(padding)) {
                items(count = state.items.size) { index ->
                    val story = state.items[index]
                    StoryRow(
                        item = story,
                        settings = settings,
                        library = library,
                        rank = if (feed.showsRank) index + 1 else null,
                        onClick = {
                            if (settings.markStoriesRead) library.markRead(story.id)
                            when (settings.storyTap) {
                                StoryTapAction.COMMENTS -> onOpenStory(story.id)
                                StoryTapAction.LINK ->
                                    openLink(context, story.primaryUrl, settings.linkTarget)
                            }
                        },
                    )
                    HorizontalDivider()
                }
                if (state.canLoadMore) {
                    item { LoadMoreRow { feeds.loadMore(feed) } }
                }
            }
        }
    }
}

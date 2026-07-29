package com.nurtrino.hackernews.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.nurtrino.hackernews.data.Library
import com.nurtrino.hackernews.data.Settings
import com.nurtrino.hackernews.data.UserViewModel
import com.nurtrino.hackernews.model.LoadPhase
import com.nurtrino.hackernews.net.SearchScope

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun UserScreen(
    username: String,
    model: UserViewModel,
    settings: Settings,
    library: Library,
    onBack: () -> Unit,
    onOpenStory: (Int) -> Unit,
) {
    val context = LocalContext.current
    val profileUrl = "https://news.ycombinator.com/user?id=$username"

    LaunchedEffect(username) { model.loadIfNeeded() }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(username) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    IconButton(onClick = { shareLink(context, profileUrl, username) }) {
                        Icon(Icons.Filled.Share, contentDescription = "Share profile")
                    }
                },
            )
        },
    ) { padding ->
        val phase = model.phase
        if (model.user == null && phase is LoadPhase.Failed) {
            EmptyState(
                icon = Icons.Filled.Warning,
                title = "Couldn't load profile",
                message = phase.message,
                actionLabel = "Try Again",
                onAction = { model.retry() },
            )
            return@Scaffold
        }

        if (model.user == null) {
            LoadingState()
            return@Scaffold
        }

        LazyColumn(modifier = Modifier.padding(padding)) {
            item {
                val user = model.user!!
                Row(
                    modifier = Modifier.fillMaxWidth().padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    SourceBadge(user.id.take(1).uppercase(), user.id, size = 52)
                    Column(modifier = Modifier.padding(start = 14.dp)) {
                        Text(
                            user.id,
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.Bold,
                        )
                        Text(
                            "${abbreviated(user.karma)} karma · joined ${shortAge(user.created)} ago",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }

                if (!user.about.isNullOrEmpty()) {
                    RichText(
                        html = user.about!!,
                        style = MaterialTheme.typography.bodyMedium,
                        modifier = Modifier.padding(horizontal = 16.dp),
                        onLinkClick = { openLink(context, it, settings.linkTarget) },
                    )
                }

                Row(
                    modifier = Modifier.padding(16.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    listOf(SearchScope.STORIES, SearchScope.COMMENTS).forEach { scope ->
                        FilterChip(
                            selected = model.scope == scope,
                            onClick = { model.setScope(scope) },
                            label = { Text(scope.title) },
                        )
                    }
                }
                HorizontalDivider()
            }

            if (model.submissions.isEmpty()) {
                item {
                    Text(
                        if (model.scope == SearchScope.COMMENTS) "No comments found."
                        else "No stories found.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.fillMaxWidth().padding(24.dp),
                    )
                }
            }

            items(count = model.submissions.size) { index ->
                val submission = model.submissions[index]
                StoryRow(
                    item = submission,
                    settings = settings,
                    library = library,
                    showSnippet = model.scope == SearchScope.COMMENTS,
                    onClick = {
                        if (settings.markStoriesRead) library.markRead(submission.id)
                        onOpenStory(submission.storyId ?: submission.id)
                    },
                )
                HorizontalDivider()
            }
        }
    }
}

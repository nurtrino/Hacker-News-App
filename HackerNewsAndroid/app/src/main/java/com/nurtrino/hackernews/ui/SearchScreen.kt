package com.nurtrino.hackernews.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import com.nurtrino.hackernews.data.Library
import com.nurtrino.hackernews.data.SearchViewModel
import com.nurtrino.hackernews.data.Settings
import com.nurtrino.hackernews.model.ItemKind
import com.nurtrino.hackernews.model.LoadPhase
import com.nurtrino.hackernews.net.SearchPeriod
import com.nurtrino.hackernews.net.SearchScope
import com.nurtrino.hackernews.net.SearchSort

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SearchScreen(
    model: SearchViewModel,
    settings: Settings,
    library: Library,
    onOpenStory: (Int) -> Unit,
) {
    var sortMenu by remember { mutableStateOf(false) }
    var periodMenu by remember { mutableStateOf(false) }

    Column(modifier = Modifier.fillMaxWidth()) {
        OutlinedTextField(
            value = model.query,
            onValueChange = { model.onQueryChanged(it) },
            placeholder = { Text("Search Hacker News") },
            leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
            trailingIcon = {
                if (model.query.isNotEmpty()) {
                    IconButton(onClick = { model.onQueryChanged("") }) {
                        Icon(Icons.Filled.Clear, contentDescription = "Clear")
                    }
                }
            },
            singleLine = true,
            keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(
                imeAction = ImeAction.Search,
            ),
            keyboardActions = androidx.compose.foundation.text.KeyboardActions(
                onSearch = { model.submit() },
            ),
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 8.dp),
        )

        LazyRow(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.padding(horizontal = 16.dp),
        ) {
            items(count = SearchScope.entries.size) { index ->
                val scope = SearchScope.entries[index]
                FilterChip(
                    selected = model.scope == scope,
                    onClick = { model.setScope(scope) },
                    label = { Text(scope.title) },
                )
            }
        }

        Row(
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            TextButton(onClick = { sortMenu = true }) { Text(model.sort.title) }
            DropdownMenu(expanded = sortMenu, onDismissRequest = { sortMenu = false }) {
                SearchSort.entries.forEach { option ->
                    DropdownMenuItem(
                        text = { Text(option.title) },
                        onClick = { sortMenu = false; model.setSort(option) },
                    )
                }
            }

            TextButton(onClick = { periodMenu = true }) {
                Icon(
                    Icons.Filled.DateRange,
                    contentDescription = null,
                    modifier = Modifier.padding(end = 4.dp),
                )
                Text(model.period.title)
            }
            DropdownMenu(expanded = periodMenu, onDismissRequest = { periodMenu = false }) {
                SearchPeriod.entries.forEach { option ->
                    DropdownMenuItem(
                        text = { Text(option.title) },
                        onClick = { periodMenu = false; model.setPeriod(option) },
                    )
                }
            }

            if (model.phase == LoadPhase.Loaded && model.totalHits > 0) {
                Text(
                    "${abbreviated(model.totalHits)} hits",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(start = 8.dp),
                )
            }
        }

        HorizontalDivider()

        val phase = model.phase
        when {
            phase == LoadPhase.Idle -> RecentSearches(model)

            model.results.isEmpty() && phase == LoadPhase.Loading -> LoadingState()

            phase is LoadPhase.Failed ->
                EmptyState(
                    icon = Icons.Filled.Warning,
                    title = "Something went wrong",
                    message = phase.message,
                    actionLabel = "Try Again",
                    onAction = { model.submit() },
                )

            model.results.isEmpty() ->
                EmptyState(
                    icon = Icons.Filled.Search,
                    title = "No results",
                    message = "Nothing matched \"${model.trimmedQuery}\". " +
                        "Try a different term or widen the time range.",
                )

            else -> LazyColumn {
                items(count = model.results.size) { index ->
                    val hit = model.results[index]
                    StoryRow(
                        item = hit,
                        settings = settings,
                        library = library,
                        showSnippet = model.scope == SearchScope.COMMENTS,
                        onClick = {
                            if (settings.markStoriesRead) library.markRead(hit.id)
                            // A comment hit opens the story it belongs to.
                            val target = if (hit.kind == ItemKind.COMMENT) {
                                hit.storyId ?: hit.id
                            } else {
                                hit.id
                            }
                            onOpenStory(target)
                        },
                    )
                    HorizontalDivider()
                }
                if (model.canLoadMore) {
                    item { LoadMoreRow { model.loadMore() } }
                }
            }
        }
    }
}

@Composable
private fun RecentSearches(model: SearchViewModel) {
    if (model.recentSearches.isEmpty()) {
        EmptyState(
            icon = Icons.Filled.Search,
            title = "Search Hacker News",
            message = "Stories and comments, all the way back to 2006.",
        )
        return
    }

    LazyColumn {
        item {
            Row(
                modifier = Modifier.fillMaxWidth().padding(start = 16.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    "RECENT",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.weight(1f),
                )
                TextButton(onClick = { model.clearRecents() }) { Text("Clear") }
            }
        }
        items(count = model.recentSearches.size) { index ->
            val text = model.recentSearches[index]
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable {
                        model.query = text
                        model.submit()
                    }
                    .padding(start = 16.dp, top = 12.dp, bottom = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(text, modifier = Modifier.weight(1f))
                IconButton(onClick = { model.removeRecent(text) }) {
                    Icon(Icons.Filled.Clear, contentDescription = "Remove")
                }
            }
            HorizontalDivider()
        }
    }
}

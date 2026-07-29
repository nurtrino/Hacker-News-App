package com.nurtrino.hackernews.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.nurtrino.hackernews.data.AppearanceMode
import com.nurtrino.hackernews.data.Library
import com.nurtrino.hackernews.data.LinkTarget
import com.nurtrino.hackernews.data.Settings
import com.nurtrino.hackernews.data.StoryTapAction
import com.nurtrino.hackernews.data.TextScale
import com.nurtrino.hackernews.model.Feed
import com.nurtrino.hackernews.net.HnApi

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(settings: Settings, library: Library) {
    val context = LocalContext.current
    var cacheCleared by remember { mutableStateOf(false) }

    Scaffold(topBar = { TopAppBar(title = { Text("Settings") }) }) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .verticalScroll(rememberScrollState()),
        ) {
            SectionHeader("Appearance")
            ChoiceRow("Theme", settings.appearance.title, AppearanceMode.entries.map { it.title }) {
                settings.setAppearance(AppearanceMode.entries[it])
            }
            ChoiceRow("Text Size", settings.textScale.title, TextScale.entries.map { it.title }) {
                settings.setTextScale(TextScale.entries[it])
            }
            SwitchRow("Source Badges", settings.showSourceBadges) {
                settings.setShowSourceBadges(it)
            }

            SectionHeader("Reading")
            ChoiceRow("Default Feed", settings.defaultFeed.title, Feed.entries.map { it.title }) {
                settings.setDefaultFeed(Feed.entries[it])
            }
            ChoiceRow(
                "Tapping a Story",
                settings.storyTap.title,
                StoryTapAction.entries.map { it.title },
            ) { settings.setStoryTap(StoryTapAction.entries[it]) }
            SwitchRow("Mark Stories as Read", settings.markStoriesRead) {
                settings.setMarkStoriesRead(it)
            }
            SwitchRow("Dim Read Stories", settings.dimReadStories) {
                settings.setDimReadStories(it)
            }

            SectionHeader("Links")
            ChoiceRow("Open Links In", settings.linkTarget.title, LinkTarget.entries.map { it.title }) {
                settings.setLinkTarget(LinkTarget.entries[it])
            }

            SectionHeader("Discussions")
            SwitchRow("Auto-Collapse Deep Replies", settings.autoCollapseDeepThreads) {
                settings.setAutoCollapseDeepThreads(it)
            }

            SectionHeader("Storage")
            InfoRow("Saved Stories", library.saved.size.toString())
            InfoRow("Stories Marked Read", library.readCount.toString())
            ActionRow("Clear Read History") { library.clearReadState() }
            ActionRow(if (cacheCleared) "Cache Cleared" else "Clear Network Cache") {
                HnApi.clearCache()
                cacheCleared = true
            }

            SectionHeader("About")
            ActionRow("Hacker News") {
                openLink(context, "https://news.ycombinator.com", settings.linkTarget)
            }
            ActionRow("Community Guidelines") {
                openLink(
                    context,
                    "https://news.ycombinator.com/newsguidelines.html",
                    settings.linkTarget,
                )
            }
            Text(
                "An unofficial reader built on the public Hacker News API and HN Search. " +
                    "Not affiliated with Y Combinator.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(16.dp),
            )
        }
    }
}

@Composable
private fun SectionHeader(title: String) {
    HorizontalDivider()
    Text(
        title.uppercase(),
        style = MaterialTheme.typography.labelSmall,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(start = 16.dp, top = 16.dp, bottom = 4.dp),
    )
}

@Composable
private fun SwitchRow(title: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onChange(!checked) }
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, modifier = Modifier.weight(1f))
        Switch(checked = checked, onCheckedChange = onChange)
    }
}

@Composable
private fun ChoiceRow(
    title: String,
    current: String,
    options: List<String>,
    onSelect: (Int) -> Unit,
) {
    var open by remember { mutableStateOf(false) }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { open = true }
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, modifier = Modifier.weight(1f))
        Text(current, color = MaterialTheme.colorScheme.onSurfaceVariant)
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            options.forEachIndexed { index, label ->
                DropdownMenuItem(
                    text = { Text(label) },
                    onClick = {
                        open = false
                        onSelect(index)
                    },
                )
            }
        }
    }
}

@Composable
private fun InfoRow(title: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, modifier = Modifier.weight(1f))
        Text(value, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun ActionRow(title: String, onClick: () -> Unit) {
    Text(
        title,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 12.dp),
    )
}

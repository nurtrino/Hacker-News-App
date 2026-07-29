package com.nurtrino.hackernews.data

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.nurtrino.hackernews.model.Feed

enum class AppearanceMode(val title: String) { SYSTEM("System"), LIGHT("Light"), DARK("Dark") }

enum class TextScale(val title: String, val factor: Float) {
    SYSTEM("System", 1.0f),
    SMALL("Small", 0.88f),
    MEDIUM("Medium", 1.0f),
    LARGE("Large", 1.15f),
    EXTRA_LARGE("Extra Large", 1.3f),
}

enum class LinkTarget(val title: String) {
    IN_APP("In-App Browser"),
    BROWSER("Default Browser"),
}

enum class StoryTapAction(val title: String) {
    COMMENTS("Open Comments"),
    LINK("Open Article"),
}

/**
 * User preferences, persisted to SharedPreferences and exposed as Compose
 * state so reads inside composables recompose on change.
 */
class Settings(context: Context) {
    private val prefs: SharedPreferences =
        context.getSharedPreferences("settings", Context.MODE_PRIVATE)

    var appearance by mutableStateOf(
        enumOr(prefs.getString("appearance", null), AppearanceMode.SYSTEM)
    )
        private set

    var textScale by mutableStateOf(
        enumOr(prefs.getString("textScale", null), TextScale.SYSTEM)
    )
        private set

    var linkTarget by mutableStateOf(
        enumOr(prefs.getString("linkTarget", null), LinkTarget.IN_APP)
    )
        private set

    var storyTap by mutableStateOf(
        enumOr(prefs.getString("storyTap", null), StoryTapAction.COMMENTS)
    )
        private set

    var defaultFeed by mutableStateOf(enumOr(prefs.getString("defaultFeed", null), Feed.TOP))
        private set

    var markStoriesRead by mutableStateOf(prefs.getBoolean("markStoriesRead", true))
        private set

    var dimReadStories by mutableStateOf(prefs.getBoolean("dimReadStories", true))
        private set

    var showSourceBadges by mutableStateOf(prefs.getBoolean("showSourceBadges", true))
        private set

    var autoCollapseDeepThreads by mutableStateOf(prefs.getBoolean("autoCollapse", false))
        private set

    fun updateAppearance(value: AppearanceMode) {
        appearance = value
        prefs.edit().putString("appearance", value.name).apply()
    }

    fun updateTextScale(value: TextScale) {
        textScale = value
        prefs.edit().putString("textScale", value.name).apply()
    }

    fun updateLinkTarget(value: LinkTarget) {
        linkTarget = value
        prefs.edit().putString("linkTarget", value.name).apply()
    }

    fun updateStoryTap(value: StoryTapAction) {
        storyTap = value
        prefs.edit().putString("storyTap", value.name).apply()
    }

    fun updateDefaultFeed(value: Feed) {
        defaultFeed = value
        prefs.edit().putString("defaultFeed", value.name).apply()
    }

    fun updateMarkStoriesRead(value: Boolean) {
        markStoriesRead = value
        prefs.edit().putBoolean("markStoriesRead", value).apply()
    }

    fun updateDimReadStories(value: Boolean) {
        dimReadStories = value
        prefs.edit().putBoolean("dimReadStories", value).apply()
    }

    fun updateShowSourceBadges(value: Boolean) {
        showSourceBadges = value
        prefs.edit().putBoolean("showSourceBadges", value).apply()
    }

    fun updateAutoCollapseDeepThreads(value: Boolean) {
        autoCollapseDeepThreads = value
        prefs.edit().putBoolean("autoCollapse", value).apply()
    }

    private inline fun <reified T : Enum<T>> enumOr(raw: String?, fallback: T): T =
        raw?.let { name -> enumValues<T>().firstOrNull { it.name == name } } ?: fallback
}

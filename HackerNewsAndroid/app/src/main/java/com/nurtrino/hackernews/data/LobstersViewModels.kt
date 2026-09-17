package com.nurtrino.hackernews.data

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.SnapshotStateList
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.nurtrino.hackernews.model.CommentNode
import com.nurtrino.hackernews.model.LoadPhase
import com.nurtrino.hackernews.model.LobstersFeed
import com.nurtrino.hackernews.model.LobstersStory
import com.nurtrino.hackernews.net.LobstersApi
import com.nurtrino.hackernews.net.userMessage
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

/**
 * One paginated lobste.rs story list.
 *
 * Unlike the Firebase feeds there's no id list to hydrate: each page comes
 * back fully populated, so this walks page numbers until one comes back empty.
 */
class LobstersFeedState(val feed: LobstersFeed) {
    val items: SnapshotStateList<LobstersStory> = mutableStateListOf()
    var phase by mutableStateOf<LoadPhase>(LoadPhase.Idle)
        private set
    var isLoadingMore by mutableStateOf(false)
        private set
    var canLoadMore by mutableStateOf(false)
        private set

    private var page = 1

    /** Lobsters' own lists stop well before this; it just guards against paging forever. */
    private val maxPages = 20

    suspend fun load(force: Boolean) {
        if (items.isEmpty()) phase = LoadPhase.Loading
        try {
            val fetched = LobstersApi.stories(feed, page = 1, forceRefresh = force)
            items.clear()
            items.addAll(fetched)
            page = 1
            canLoadMore = fetched.isNotEmpty()
            phase = LoadPhase.Loaded
        } catch (error: Throwable) {
            // A failed refresh isn't fatal when there's already content.
            phase = if (items.isEmpty()) LoadPhase.Failed(error.userMessage()) else LoadPhase.Loaded
        }
    }

    suspend fun loadMore() {
        if (!canLoadMore || isLoadingMore || phase != LoadPhase.Loaded) return
        isLoadingMore = true
        val nextPage = page + 1
        try {
            val fetched = LobstersApi.stories(feed, page = nextPage)
            // The active list reorders between pages, so a story can show up
            // on two consecutive pages. Drop the repeats.
            val seen = items.mapTo(HashSet()) { it.shortId }
            items.addAll(fetched.filter { seen.add(it.shortId) })
            page = nextPage
            canLoadMore = fetched.isNotEmpty() && nextPage < maxPages
        } catch (_: Throwable) {
            // Keep what's on screen; the row will retry when it scrolls back.
        } finally {
            isLoadingMore = false
        }
    }
}

/** Holds one [LobstersFeedState] per feed, plus which feed the tab is showing. */
class LobstersViewModel : ViewModel() {
    private val states = mutableMapOf<LobstersFeed, LobstersFeedState>()

    /** Kept here rather than in the screen so it survives leaving the tab. */
    var selectedFeed by mutableStateOf(LobstersFeed.ACTIVE)

    fun state(feed: LobstersFeed): LobstersFeedState = states.getOrPut(feed) { LobstersFeedState(feed) }

    fun loadIfNeeded(feed: LobstersFeed) {
        val state = state(feed)
        if (state.items.isNotEmpty() || state.phase == LoadPhase.Loading) return
        viewModelScope.launch { state.load(force = false) }
    }

    fun refresh(feed: LobstersFeed, onDone: () -> Unit = {}) {
        viewModelScope.launch {
            state(feed).load(force = true)
            onDone()
        }
    }

    fun loadMore(feed: LobstersFeed) {
        viewModelScope.launch { state(feed).loadMore() }
    }

    /** A story already on screen, so the thread can render its header at once. */
    fun story(shortId: String): LobstersStory? =
        states.values.firstNotNullOfOrNull { state -> state.items.firstOrNull { it.shortId == shortId } }
}

/**
 * Loads and manages one Lobsters story's comment thread.
 *
 * The story endpoint returns the whole discussion, thread-sorted, so there's
 * no index-vs-canonical dance here — one request, then collapse state.
 */
class LobstersThreadViewModel(private val shortId: String, initial: LobstersStory?) : ViewModel() {
    var story by mutableStateOf(initial ?: LobstersStory(shortId = shortId, title = "Loading…"))
        private set
    var nodes by mutableStateOf<List<CommentNode>>(emptyList())
        private set
    var phase by mutableStateOf<LoadPhase>(LoadPhase.Idle)
        private set

    private val collapsed = mutableStateListOf<Int>()
    private var job: Job? = null

    /** Comments with collapsed subtrees skipped. */
    val visibleNodes: List<CommentNode>
        get() {
            if (collapsed.isEmpty()) return nodes
            val result = ArrayList<CommentNode>(nodes.size)
            var skipBelowDepth: Int? = null
            for (node in nodes) {
                val depth = skipBelowDepth
                if (depth != null) {
                    if (node.depth > depth) continue
                    skipBelowDepth = null
                }
                result.add(node)
                if (collapsed.contains(node.id)) skipBelowDepth = node.depth
            }
            return result
        }

    fun isCollapsed(id: Int): Boolean = collapsed.contains(id)

    fun toggleCollapse(node: CommentNode) {
        if (!collapsed.remove(node.id)) collapsed.add(node.id)
    }

    val isFullyCollapsed: Boolean
        get() = nodes.isNotEmpty() && nodes.filter { it.isTopLevel }
            .all { it.descendantCount == 0 || collapsed.contains(it.id) }

    fun collapseAll() {
        collapsed.clear()
        collapsed.addAll(nodes.filter { it.isTopLevel && it.descendantCount > 0 }.map { it.id })
    }

    fun expandAll() = collapsed.clear()

    fun loadIfNeeded(autoCollapseDeep: Boolean) {
        if (nodes.isNotEmpty() || phase == LoadPhase.Loading) return
        start(force = false, autoCollapseDeep = autoCollapseDeep)
    }

    fun retry(autoCollapseDeep: Boolean) = start(force = true, autoCollapseDeep = autoCollapseDeep)

    private fun start(force: Boolean, autoCollapseDeep: Boolean) {
        job?.cancel()
        job = viewModelScope.launch { load(force, autoCollapseDeep) }
    }

    private suspend fun load(force: Boolean, autoCollapseDeep: Boolean) {
        if (nodes.isEmpty()) phase = LoadPhase.Loading
        try {
            val (fresh, comments) = LobstersApi.thread(shortId, force)
            if (fresh != null) story = fresh
            nodes = comments
            collapsed.clear()
            if (autoCollapseDeep) {
                collapsed.addAll(comments.filter { it.depth >= 2 && it.descendantCount > 0 }.map { it.id })
            }
            phase = LoadPhase.Loaded
        } catch (error: Throwable) {
            phase = if (nodes.isEmpty()) LoadPhase.Failed(error.userMessage()) else LoadPhase.Loaded
        }
    }
}

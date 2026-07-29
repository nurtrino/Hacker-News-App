package com.nurtrino.hackernews.data

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.SnapshotStateList
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.nurtrino.hackernews.model.CommentNode
import com.nurtrino.hackernews.model.Feed
import com.nurtrino.hackernews.model.HnUser
import com.nurtrino.hackernews.model.Item
import com.nurtrino.hackernews.model.LoadPhase
import com.nurtrino.hackernews.model.withDescendantCounts
import com.nurtrino.hackernews.net.AlgoliaApi
import com.nurtrino.hackernews.net.HnApi
import com.nurtrino.hackernews.net.SearchPeriod
import com.nurtrino.hackernews.net.SearchScope
import com.nurtrino.hackernews.net.SearchSort
import com.nurtrino.hackernews.net.userMessage
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * One paginated story list per feed.
 *
 * The Firebase API hands back up to 500 ids at once and nothing else, so this
 * keeps the id list and hydrates it a page at a time.
 */
class FeedState(val feed: Feed) {
    val items: SnapshotStateList<Item> = mutableStateListOf()
    var phase by mutableStateOf<LoadPhase>(LoadPhase.Idle)
        private set
    var isLoadingMore by mutableStateOf(false)
        private set

    private var ids: List<Int> = emptyList()
    private var cursor = 0
    private val pageSize = 25

    val canLoadMore: Boolean get() = cursor < ids.size

    suspend fun load(force: Boolean) {
        if (items.isEmpty()) phase = LoadPhase.Loading
        try {
            val fetchedIds = HnApi.ids(feed, force)
            ids = fetchedIds
            cursor = 0

            val page = fetchedIds.take(pageSize)
            val fetched = HnApi.items(page, force)
            cursor = page.size
            items.clear()
            items.addAll(fetched.filter { !it.deleted })
            phase = LoadPhase.Loaded
        } catch (error: Throwable) {
            // A failed refresh isn't fatal when there's already content.
            phase = if (items.isEmpty()) LoadPhase.Failed(error.userMessage()) else LoadPhase.Loaded
        }
    }

    suspend fun loadMore() {
        if (!canLoadMore || isLoadingMore || phase != LoadPhase.Loaded) return
        isLoadingMore = true
        try {
            val page = ids.subList(cursor, minOf(cursor + pageSize, ids.size)).toList()
            val fetched = HnApi.items(page)
            cursor += page.size
            items.addAll(fetched.filter { !it.deleted })
        } catch (_: Throwable) {
            // Keep what's on screen; the row will retry when it scrolls back.
        } finally {
            isLoadingMore = false
        }
    }
}

/** Holds one [FeedState] per feed so switching tabs keeps scroll and cache. */
class FeedsViewModel : ViewModel() {
    private val states = mutableMapOf<Feed, FeedState>()

    fun state(feed: Feed): FeedState = states.getOrPut(feed) { FeedState(feed) }

    fun loadIfNeeded(feed: Feed) {
        val state = state(feed)
        if (state.items.isNotEmpty() || state.phase == LoadPhase.Loading) return
        viewModelScope.launch { state.load(force = false) }
    }

    fun refresh(feed: Feed, onDone: () -> Unit = {}) {
        viewModelScope.launch {
            state(feed).load(force = true)
            onDone()
        }
    }

    fun loadMore(feed: Feed) {
        viewModelScope.launch { state(feed).loadMore() }
    }
}

/**
 * Loads and manages one story's comment thread.
 *
 * The whole tree comes from HN Search in a single request. That index lags
 * live posts by a few minutes, so anything it can't answer for falls back to
 * walking the Firebase API level by level.
 */
class ThreadViewModel(private val storyId: Int) : ViewModel() {
    var story by mutableStateOf(Item(id = storyId))
        private set
    var nodes by mutableStateOf<List<CommentNode>>(emptyList())
        private set
    var phase by mutableStateOf<LoadPhase>(LoadPhase.Idle)
        private set

    private val collapsed = mutableStateListOf<Int>()
    private var job: Job? = null
    private val maxFallbackDepth = 8

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

    fun refresh(autoCollapseDeep: Boolean, onDone: () -> Unit) {
        job?.cancel()
        job = viewModelScope.launch {
            load(force = true, autoCollapseDeep = autoCollapseDeep)
            onDone()
        }
    }

    private fun start(force: Boolean, autoCollapseDeep: Boolean) {
        job?.cancel()
        job = viewModelScope.launch { load(force, autoCollapseDeep) }
    }

    private suspend fun load(force: Boolean, autoCollapseDeep: Boolean) {
        if (nodes.isEmpty()) phase = LoadPhase.Loading

        // Fill in fields a search result or saved copy may be missing.
        if (force || story.kids.isEmpty()) {
            runCatching { HnApi.item(storyId, force) }.getOrNull()?.let { story = merge(it, story) }
        }

        val indexed = runCatching { AlgoliaApi.thread(storyId) }.getOrNull()
        if (indexed != null) {
            indexed.first?.let { story = merge(it, story) }
            val comments = indexed.second
            if (comments.isNotEmpty() || story.kids.isEmpty()) {
                apply(comments, autoCollapseDeep)
                return
            }
        }

        val comments = runCatching { children(story.kids, 0) }.getOrDefault(emptyList())
            .withDescendantCounts()
        if (comments.isEmpty() && story.kids.isNotEmpty()) {
            phase = LoadPhase.Failed("Couldn't load the discussion.")
        } else {
            apply(comments, autoCollapseDeep)
        }
    }

    private fun apply(comments: List<CommentNode>, autoCollapseDeep: Boolean) {
        nodes = comments
        collapsed.clear()
        if (autoCollapseDeep) {
            collapsed.addAll(comments.filter { it.depth >= 2 && it.descendantCount > 0 }.map { it.id })
        }
        phase = LoadPhase.Loaded
    }

    /** Level-by-level walk of the official API, for stories search hasn't indexed. */
    private suspend fun children(ids: List<Int>, depth: Int): List<CommentNode> {
        if (ids.isEmpty() || depth > maxFallbackDepth) return emptyList()
        val fetched = HnApi.items(ids)
        val result = mutableListOf<CommentNode>()
        for (item in fetched) {
            val isDeleted = item.deleted || (item.text.isNullOrEmpty() && item.by == null)
            if (isDeleted && item.kids.isEmpty()) continue
            result.add(
                CommentNode(
                    id = item.id,
                    parent = item.parent,
                    author = item.by,
                    html = item.text.orEmpty(),
                    time = item.time,
                    depth = depth,
                    isDeleted = isDeleted,
                )
            )
            if (item.kids.isNotEmpty()) result.addAll(children(item.kids, depth + 1))
        }
        return result
    }

    /**
     * Search hits carry points and titles but no kids; the Firebase record
     * carries kids but search is fresher on scores. Take the best of both.
     */
    private fun merge(incoming: Item, existing: Item): Item = existing.copy(
        kind = if (incoming.kind != com.nurtrino.hackernews.model.ItemKind.UNKNOWN) incoming.kind else existing.kind,
        deleted = incoming.deleted || existing.deleted,
        dead = incoming.dead || existing.dead,
        by = incoming.by ?: existing.by,
        time = incoming.time ?: existing.time,
        text = incoming.text?.takeIf { it.isNotEmpty() } ?: existing.text,
        kids = incoming.kids.ifEmpty { existing.kids },
        url = incoming.url?.takeIf { it.isNotEmpty() } ?: existing.url,
        score = incoming.score ?: existing.score,
        title = incoming.title?.takeIf { it.isNotEmpty() } ?: existing.title,
        descendants = incoming.descendants ?: existing.descendants,
    )
}

/** Debounced, paginated full-text search. */
class SearchViewModel : ViewModel() {
    var query by mutableStateOf("")
    var scope by mutableStateOf(SearchScope.STORIES)
        private set
    var sort by mutableStateOf(SearchSort.RELEVANCE)
        private set
    var period by mutableStateOf(SearchPeriod.ALL_TIME)
        private set

    val results = mutableStateListOf<Item>()
    var phase by mutableStateOf<LoadPhase>(LoadPhase.Idle)
        private set
    var totalHits by mutableStateOf(0)
        private set
    val recentSearches = mutableStateListOf<String>()

    private var page = 0
    private var totalPages = 0
    private var job: Job? = null
    private var isLoadingMore = false

    val canLoadMore: Boolean get() = page + 1 < totalPages
    val trimmedQuery: String get() = query.trim()

    fun updateScope(value: SearchScope) { scope = value; rerun() }
    fun updateSort(value: SearchSort) { sort = value; rerun() }
    fun updatePeriod(value: SearchPeriod) { period = value; rerun() }

    /** Called on every keystroke; waits for a pause before hitting the network. */
    fun onQueryChanged(value: String) {
        query = value
        job?.cancel()
        if (trimmedQuery.isEmpty()) {
            results.clear()
            totalHits = 0
            phase = LoadPhase.Idle
            return
        }
        job = viewModelScope.launch {
            delay(350)
            run(reset = true)
        }
    }

    /** Explicit submit skips the debounce and records the term. */
    fun submit() {
        job?.cancel()
        if (trimmedQuery.isEmpty()) return
        remember(trimmedQuery)
        job = viewModelScope.launch { run(reset = true) }
    }

    fun loadMore() {
        if (!canLoadMore || isLoadingMore || phase != LoadPhase.Loaded) return
        isLoadingMore = true
        viewModelScope.launch { run(reset = false) }
    }

    private fun rerun() {
        if (trimmedQuery.isEmpty()) return
        job?.cancel()
        job = viewModelScope.launch { run(reset = true) }
    }

    private suspend fun run(reset: Boolean) {
        val text = trimmedQuery
        if (text.isEmpty()) return
        if (reset) {
            page = 0
            phase = LoadPhase.Loading
        }
        try {
            val response = AlgoliaApi.search(
                query = text,
                scope = scope,
                sort = sort,
                period = period,
                page = if (reset) 0 else page + 1,
            )
            if (text != trimmedQuery) return
            page = response.page
            totalPages = response.totalPages
            totalHits = response.totalHits
            if (reset) results.clear()
            results.addAll(response.items)
            phase = LoadPhase.Loaded
        } catch (error: Throwable) {
            if (reset) results.clear()
            phase = LoadPhase.Failed(error.userMessage())
        } finally {
            isLoadingMore = false
        }
    }

    private fun remember(text: String) {
        recentSearches.removeAll { it.equals(text, ignoreCase = true) }
        recentSearches.add(0, text)
        while (recentSearches.size > 12) recentSearches.removeAt(recentSearches.size - 1)
    }

    fun removeRecent(text: String) {
        recentSearches.remove(text)
    }

    fun clearRecents() = recentSearches.clear()
}

/** A profile plus that account's recent submissions. */
class UserViewModel(private val username: String) : ViewModel() {
    var user by mutableStateOf<HnUser?>(null)
        private set
    var phase by mutableStateOf<LoadPhase>(LoadPhase.Idle)
        private set
    var scope by mutableStateOf(SearchScope.STORIES)
        private set

    val submissions = mutableStateListOf<Item>()

    fun loadIfNeeded() {
        if (user != null || phase == LoadPhase.Loading) return
        viewModelScope.launch {
            phase = LoadPhase.Loading
            try {
                user = HnApi.user(username)
                phase = if (user == null) {
                    LoadPhase.Failed("That account doesn't exist.")
                } else {
                    LoadPhase.Loaded
                }
            } catch (error: Throwable) {
                phase = LoadPhase.Failed(error.userMessage())
                return@launch
            }
            fetchSubmissions()
        }
    }

    fun retry() {
        phase = LoadPhase.Idle
        loadIfNeeded()
    }

    fun updateScope(value: SearchScope) {
        if (value == scope) return
        scope = value
        viewModelScope.launch { fetchSubmissions() }
    }

    private suspend fun fetchSubmissions() {
        submissions.clear()
        val response = runCatching { AlgoliaApi.submissions(username, scope) }.getOrNull() ?: return
        submissions.addAll(response.items)
    }
}

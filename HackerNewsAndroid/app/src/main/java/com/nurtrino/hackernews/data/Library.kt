package com.nurtrino.hackernews.data

import android.content.Context
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateMapOf
import com.nurtrino.hackernews.model.Item
import com.nurtrino.hackernews.net.Http
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import java.io.File

/**
 * Saved stories and read state, persisted as JSON in the app's files dir.
 *
 * Both lists are small — saved posts are user-curated and read ids are capped
 * — so they're held fully in memory and written back on a debounce.
 */
class Library(context: Context) {
    private val directory = File(context.filesDir, "library").apply { mkdirs() }
    private val savedFile = File(directory, "saved.json")
    private val readFile = File(directory, "read.json")

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var writeJob: Job? = null

    /** Newest first. */
    val saved = mutableStateListOf<Item>()

    /** Backing set for O(1) lookups from list rows; the value is ignored. */
    private val readIds = mutableStateMapOf<Int, Unit>()

    /** Read ids in insertion order, newest first, so the cap trims the oldest. */
    private val readOrder = ArrayDeque<Int>()
    private val readCap = 5_000

    init {
        runCatching {
            if (savedFile.exists()) {
                saved.addAll(Http.json.decodeFromString<List<Item>>(savedFile.readText()))
            }
        }
        runCatching {
            if (readFile.exists()) {
                val ids = Http.json.decodeFromString<List<Int>>(readFile.readText())
                readOrder.addAll(ids)
                ids.forEach { readIds[it] = Unit }
            }
        }
    }

    // Saved stories

    fun isSaved(id: Int): Boolean = saved.any { it.id == id }

    /** Returns true if the item ended up saved. */
    fun toggleSave(item: Item): Boolean {
        val index = saved.indexOfFirst { it.id == item.id }
        val nowSaved = if (index >= 0) {
            saved.removeAt(index)
            false
        } else {
            saved.add(0, item)
            true
        }
        scheduleWrite()
        return nowSaved
    }

    fun remove(id: Int) {
        if (saved.removeAll { it.id == id }) scheduleWrite()
    }

    fun clearSaved() {
        saved.clear()
        scheduleWrite()
    }

    /** Keeps a saved copy current once the full item has been fetched. */
    fun refreshSaved(item: Item) {
        val index = saved.indexOfFirst { it.id == item.id }
        if (index < 0) return
        saved[index] = item
        scheduleWrite()
    }

    // Read state

    fun isRead(id: Int): Boolean = readIds.containsKey(id)

    fun markRead(id: Int) {
        if (readIds.containsKey(id)) return
        readIds[id] = Unit
        readOrder.addFirst(id)
        while (readOrder.size > readCap) {
            readIds.remove(readOrder.removeLast())
        }
        scheduleWrite()
    }

    val readCount: Int get() = readIds.size

    fun clearReadState() {
        readIds.clear()
        readOrder.clear()
        scheduleWrite()
    }

    // Persistence

    /** Coalesces bursts of changes into one disk write. */
    private fun scheduleWrite() {
        writeJob?.cancel()
        val savedSnapshot = saved.toList()
        val readSnapshot = readOrder.toList()
        writeJob = scope.launch {
            delay(400)
            write(savedSnapshot, readSnapshot)
        }
    }

    /** Called when the app stops, so nothing is lost to a pending debounce. */
    fun flush() {
        writeJob?.cancel()
        val savedSnapshot = saved.toList()
        val readSnapshot = readOrder.toList()
        scope.launch { write(savedSnapshot, readSnapshot) }
    }

    private fun write(savedSnapshot: List<Item>, readSnapshot: List<Int>) {
        runCatching { savedFile.writeText(Http.json.encodeToString(savedSnapshot)) }
        runCatching { readFile.writeText(Http.json.encodeToString(readSnapshot)) }
    }
}

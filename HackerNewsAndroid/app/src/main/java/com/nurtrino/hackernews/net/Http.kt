package com.nurtrino.hackernews.net

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import okhttp3.Cache
import okhttp3.CacheControl
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.io.IOException
import java.util.concurrent.TimeUnit

class HttpException(val status: Int) : IOException("The server returned status $status.")

class OfflineException : IOException("You appear to be offline.")

/**
 * One shared OkHttp client with a disk cache, standing in for the
 * `URLCache` the iOS build leans on.
 */
object Http {
    val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
        coerceInputValues = true
        encodeDefaults = true
    }

    @Volatile
    private var client: OkHttpClient? = null

    fun init(context: Context) {
        if (client != null) return
        synchronized(this) {
            if (client != null) return
            val cacheDir = File(context.cacheDir, "http")
            client = OkHttpClient.Builder()
                .cache(Cache(cacheDir, 128L * 1024 * 1024))
                .connectTimeout(20, TimeUnit.SECONDS)
                .readTimeout(20, TimeUnit.SECONDS)
                .callTimeout(45, TimeUnit.SECONDS)
                .retryOnConnectionFailure(true)
                .build()
        }
    }

    private fun requireClient(): OkHttpClient =
        client ?: throw IllegalStateException("Http.init(context) was never called")

    /** GET the URL as text. [forceRefresh] bypasses the disk cache. */
    suspend fun getString(url: String, forceRefresh: Boolean = false): String =
        withContext(Dispatchers.IO) {
            val builder = Request.Builder().url(url)
            if (forceRefresh) builder.cacheControl(CacheControl.FORCE_NETWORK)
            try {
                requireClient().newCall(builder.build()).execute().use { response ->
                    if (!response.isSuccessful) throw HttpException(response.code)
                    response.body?.string().orEmpty()
                }
            } catch (error: HttpException) {
                throw error
            } catch (error: IOException) {
                // OkHttp surfaces DNS/connect failures as plain IOExceptions;
                // for the user they all mean the same thing.
                throw OfflineException()
            }
        }

    fun clearCache() {
        runCatching { client?.cache?.evictAll() }
    }
}

/** Human-readable message for anything thrown out of the network layer. */
fun Throwable.userMessage(): String = when (this) {
    is OfflineException -> "You appear to be offline."
    is HttpException -> "The server returned status $status."
    else -> message ?: "Something went wrong."
}

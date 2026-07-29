package com.nurtrino.hackernews.ui

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.browser.customtabs.CustomTabsIntent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import com.nurtrino.hackernews.data.LinkTarget
import kotlin.math.abs

/** Everything outbound goes through here so the link preference is honoured once. */
fun openLink(context: Context, url: String, target: LinkTarget) {
    val uri = runCatching { Uri.parse(url) }.getOrNull() ?: return
    when (target) {
        LinkTarget.IN_APP -> {
            val intent = CustomTabsIntent.Builder()
                .setShowTitle(true)
                .setUrlBarHidingEnabled(true)
                .build()
            runCatching { intent.launchUrl(context, uri) }
                .onFailure { openExternally(context, uri) }
        }
        LinkTarget.BROWSER -> openExternally(context, uri)
    }
}

private fun openExternally(context: Context, uri: Uri) {
    val intent = Intent(Intent.ACTION_VIEW, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    try {
        ContextCompat.startActivity(context, intent, null)
    } catch (_: ActivityNotFoundException) {
        // No browser installed; nothing sensible to fall back to.
    }
}

fun shareLink(context: Context, url: String, subject: String? = null) {
    val intent = Intent(Intent.ACTION_SEND).apply {
        type = "text/plain"
        putExtra(Intent.EXTRA_TEXT, url)
        if (subject != null) putExtra(Intent.EXTRA_SUBJECT, subject)
    }
    runCatching {
        ContextCompat.startActivity(context, Intent.createChooser(intent, "Share").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK), null)
    }
}

fun copyToClipboard(context: Context, text: String) {
    val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as? android.content.ClipboardManager
    clipboard?.setPrimaryClip(android.content.ClipData.newPlainText("Hacker News", text))
}

// Formatting

/** Compact age in HN's own idiom: `5m`, `3h`, `2d`, `4mo`, `2y`. */
fun shortAge(epochSeconds: Long?, nowSeconds: Long = System.currentTimeMillis() / 1000): String {
    if (epochSeconds == null) return ""
    val seconds = (nowSeconds - epochSeconds).coerceAtLeast(0)
    return when {
        seconds < 60 -> "${seconds}s"
        seconds < 3_600 -> "${seconds / 60}m"
        seconds < 86_400 -> "${seconds / 3_600}h"
        seconds < 2_592_000 -> "${seconds / 86_400}d"
        seconds < 31_536_000 -> "${seconds / 2_592_000}mo"
        else -> "${seconds / 31_536_000}y"
    }
}

/** `1234` -> `1.2k`. */
fun abbreviated(value: Int): String = when {
    value < 1_000 -> value.toString()
    value < 1_000_000 -> {
        val scaled = value / 1000.0
        if (scaled < 10) String.format("%.1fk", scaled) else String.format("%.0fk", scaled)
    }
    else -> String.format("%.1fM", value / 1_000_000.0)
}

fun pluralized(count: Int, singular: String, plural: String = singular + "s"): String =
    if (count == 1) "$count $singular" else "$count $plural"

// Shared pieces

@Composable
fun EmptyState(
    icon: ImageVector,
    title: String,
    message: String? = null,
    actionLabel: String? = null,
    onAction: (() -> Unit)? = null,
) {
    Column(
        modifier = Modifier.fillMaxSize().padding(28.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Icon(
            icon,
            contentDescription = null,
            modifier = Modifier.size(44.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
        )
        Text(
            title,
            style = MaterialTheme.typography.titleMedium,
            modifier = Modifier.padding(top = 14.dp),
        )
        if (message != null) {
            Text(
                message,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(top = 8.dp),
            )
        }
        if (actionLabel != null && onAction != null) {
            Button(onClick = onAction, modifier = Modifier.padding(top = 16.dp)) {
                Text(actionLabel)
            }
        }
    }
}

@Composable
fun LoadingState(label: String? = null) {
    Column(
        modifier = Modifier.fillMaxSize(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        CircularProgressIndicator()
        if (label != null) {
            Text(
                label,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 12.dp),
            )
        }
    }
}

/** Row at the bottom of a paginated list; asks for the next page on appear. */
@Composable
fun LoadMoreRow(onAppear: () -> Unit) {
    androidx.compose.runtime.LaunchedEffect(Unit) { onAppear() }
    Box(
        modifier = Modifier.fillMaxWidth().padding(vertical = 14.dp),
        contentAlignment = Alignment.Center,
    ) {
        CircularProgressIndicator(modifier = Modifier.size(22.dp), strokeWidth = 2.dp)
    }
}

/** Small coloured square with the source's initial. */
@Composable
fun SourceBadge(label: String, seed: String, size: Int = 34) {
    val color = stableColor(seed)
    Box(
        modifier = Modifier
            .size(size.dp)
            .background(color.copy(alpha = 0.16f), RoundedCornerShape((size * 0.28f).dp)),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            label,
            color = color,
            fontSize = (size * 0.45f).sp,
            style = MaterialTheme.typography.titleSmall,
        )
    }
}

/** `12 points`-style metadata chip. */
@Composable
fun MetaLabel(
    icon: ImageVector,
    text: String,
    tint: androidx.compose.ui.graphics.Color = MaterialTheme.colorScheme.onSurfaceVariant,
) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, contentDescription = null, modifier = Modifier.size(12.dp), tint = tint)
        Text(
            text,
            style = MaterialTheme.typography.labelSmall,
            color = tint,
            maxLines = 1,
            modifier = Modifier.padding(start = 3.dp),
        )
    }
}

internal fun hashIndex(value: Int, bound: Int): Int = abs(value) % bound

package com.opendroids.tourbot.ui.components

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.unit.dp
import kotlin.math.abs

@Composable
fun WaypointCarousel(
    waypointIds: List<String>,
    currentWaypointId: String,
    modifier: Modifier = Modifier
) {
    if (waypointIds.isEmpty()) return

    val listState = rememberLazyListState()
    val centeredItemIndex = waypointIds.indexOf(currentWaypointId)

    // The "infinite" carousel is achieved by creating a very large list
    // and starting in the middle.
    val virtualListSize = Int.MAX_VALUE
    val startPosition = virtualListSize / 2

    // This effect runs once to snap to the initial position without animation.
    LaunchedEffect(key1 = centeredItemIndex) {
        val targetIndex = startPosition + centeredItemIndex
        listState.scrollToItem(targetIndex)
    }

    LazyRow(
        state = listState,
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically
    ) {
        items(virtualListSize) { index ->
            val waypointIndex = (index - startPosition).mod(waypointIds.size)
            val waypointId = waypointIds[waypointIndex]

            // Calculate the distance from the "true" center of the visible items
            val layoutInfo = listState.layoutInfo
            val center = layoutInfo.viewportEndOffset / 2f
            val itemInfo = layoutInfo.visibleItemsInfo.find { it.index == index }
            
            val distanceFromCenter = if (itemInfo != null) {
                val itemCenter = itemInfo.offset + itemInfo.size / 2f
                abs(itemCenter - center)
            } else {
                // Estimate for items not currently visible
                (abs(index - (listState.firstVisibleItemIndex + layoutInfo.visibleItemsInfo.size / 2))) * 100f
            }

            val scale = (1.0f - (distanceFromCenter / center).coerceIn(0f, 1f) * 0.5f)
            val alpha = (1.0f - (distanceFromCenter / center).coerceIn(0f, 1f) * 0.8f)

            Box(
                modifier = Modifier
                    .width(150.dp) // Give each item a fixed width for consistent spacing
                    .graphicsLayer {
                        scaleX = scale
                        scaleY = scale
                        this.alpha = alpha
                    },
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = waypointId,
                    style = MaterialTheme.typography.headlineMedium,
                    color = MaterialTheme.colorScheme.onSurface
                )
            }
        }
    }
}

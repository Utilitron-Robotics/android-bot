package com.opendroids.tourbot.ui.components.pointcloud

import android.opengl.GLSurfaceView
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver

/**
 * Jetpack Compose wrapper for the 3D point cloud face animation.
 *
 * Renders a swirling globe of particles that coalesces into a female face
 * and animates mouth movements synced to audio amplitude.
 *
 * @param amplitude Audio amplitude value (0-15000 range from AudioPlayer)
 * @param modifier Compose modifier for layout
 * @param skipIntro If true, skips the swirling intro and shows face immediately
 */
@Composable
fun PointCloudFace(
    amplitude: Int,
    modifier: Modifier = Modifier,
    skipIntro: Boolean = false
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current

    // Normalize amplitude to 0-1 range
    val normalizedAmplitude = remember(amplitude) {
        val normalized = (amplitude / 15000f).coerceIn(0f, 1f)
        // Apply dead zone for silence
        if (normalized < 0.05f) 0f else normalized
    }

    // Create renderer instance
    val renderer = remember { PointCloudRenderer() }

    // Update amplitude on renderer
    LaunchedEffect(normalizedAmplitude) {
        renderer.amplitude = normalizedAmplitude
    }

    // Skip intro if requested
    LaunchedEffect(skipIntro) {
        if (skipIntro) {
            renderer.skipToFace()
        }
    }

    // GLSurfaceView reference for lifecycle management
    var glSurfaceView by remember { mutableStateOf<GLSurfaceView?>(null) }

    // Handle lifecycle events
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_RESUME -> glSurfaceView?.onResume()
                Lifecycle.Event.ON_PAUSE -> glSurfaceView?.onPause()
                else -> {}
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
        }
    }

    AndroidView(
        modifier = modifier.fillMaxSize(),
        factory = { ctx ->
            GLSurfaceView(ctx).apply {
                // Use OpenGL ES 2.0
                setEGLContextClientVersion(2)

                // Enable alpha for transparent background
                setEGLConfigChooser(8, 8, 8, 8, 16, 0)
                holder.setFormat(android.graphics.PixelFormat.TRANSLUCENT)
                setZOrderOnTop(false)

                // Set renderer
                setRenderer(renderer)

                // Continuous rendering for smooth animation
                renderMode = GLSurfaceView.RENDERMODE_CONTINUOUSLY

                glSurfaceView = this
            }
        },
        update = { view ->
            // View updates happen through renderer.amplitude
        }
    )
}

/**
 * Preview-friendly version that shows a placeholder in preview mode.
 */
@Composable
fun PointCloudFacePreview(
    modifier: Modifier = Modifier
) {
    // In preview, just show a placeholder
    androidx.compose.foundation.Canvas(modifier = modifier.fillMaxSize()) {
        drawCircle(
            color = androidx.compose.ui.graphics.Color.Cyan,
            radius = size.minDimension / 3,
            alpha = 0.5f
        )
    }
}

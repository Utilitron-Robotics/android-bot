package com.opendroids.tourbot.ui.components.pointcloud

import android.Manifest
import android.opengl.GLSurfaceView
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import com.google.accompanist.permissions.ExperimentalPermissionsApi
import com.google.accompanist.permissions.rememberPermissionState

/**
 * Jetpack Compose wrapper for the 3D point cloud face animation.
 *
 * Renders a swirling globe of particles that coalesces into a female face
 * with text-driven phoneme lip sync for realistic speech animation.
 *
 * @param amplitude Audio amplitude value (0-15000 range from AudioPlayer)
 * @param isSpeaking Whether the robot is currently speaking
 * @param modifier Compose modifier for layout
 * @param skipIntro If true, skips the swirling intro and shows face immediately
 */
@OptIn(ExperimentalPermissionsApi::class)
@Composable
fun PointCloudFace(
    amplitude: Int,
    isSpeaking: Boolean,
    modifier: Modifier = Modifier,
    skipIntro: Boolean = false
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current

    val recordAudioPermissionState = rememberPermissionState(Manifest.permission.RECORD_AUDIO)

    LaunchedEffect(Unit) {
        recordAudioPermissionState.launchPermissionRequest()
    }

    // Create renderer instance
    val renderer = remember { PointCloudRenderer() }

    // Update amplitude on renderer directly
    LaunchedEffect(amplitude) {
        val normalized = (amplitude / 5000f).coerceIn(0f, 1f)
        renderer.amplitude = normalized
    }

    // Pass speaking state to renderer
    LaunchedEffect(isSpeaking) {
        renderer.isSpeaking = isSpeaking
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

    if (recordAudioPermissionState.hasPermission) {
        AndroidView(
            modifier = modifier.fillMaxSize(),
            factory = { ctx ->
                GLSurfaceView(ctx).apply {
                    setEGLContextClientVersion(2)
                    setEGLConfigChooser(8, 8, 8, 8, 16, 0)
                    holder.setFormat(android.graphics.PixelFormat.TRANSLUCENT)
                    setZOrderOnTop(false)
                    setRenderer(renderer)
                    renderMode = GLSurfaceView.RENDERMODE_CONTINUOUSLY
                    glSurfaceView = this
                }
            },
            update = { view ->
                // View updates happen via LaunchedEffects
            }
        )
    }
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

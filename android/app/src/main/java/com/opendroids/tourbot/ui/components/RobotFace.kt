package com.opendroids.tourbot.ui.components

import androidx.compose.animation.core.*
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import kotlinx.coroutines.delay
import kotlin.random.Random

@Composable
fun RobotFace(
    amplitude: Int,
    modifier: Modifier = Modifier
) {
    var isBlinking by remember { mutableStateOf(false) }
    val pupilOffset = remember { Animatable(Offset.Zero, Offset.VectorConverter) } // Corrected Animatable

    // Blinking animation
    LaunchedEffect(Unit) {
        while (true) {
            delay(Random.nextLong(2000, 5000))
            isBlinking = true
            delay(150)
            isBlinking = false
        }
    }

    // Pupil "looking around" animation
    LaunchedEffect(Unit) {
        while (true) {
            delay(Random.nextLong(1500, 4000)) // Wait for a bit
            val maxX = 15f
            val maxY = 10f
            pupilOffset.animateTo(
                targetValue = Offset(
                    x = Random.nextFloat() * 2 * maxX - maxX,
                    y = Random.nextFloat() * 2 * maxY - maxY
                ),
                animationSpec = tween(durationMillis = 500, easing = EaseInOut)
            )
            delay(1000) // Hold the gaze
            pupilOffset.animateTo(
                targetValue = Offset.Zero,
                animationSpec = tween(durationMillis = 300, easing = EaseInOut)
            )
        }
    }

    // Eyebrow animation
    val eyebrowAnimationProgress by rememberInfiniteTransition(label = "eyebrowOffset").animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 1500, easing = LinearEasing),
            repeatMode = RepeatMode.Reverse
        ), label = "eyebrowAnimationProgress"
    )

    Canvas(modifier = modifier.fillMaxSize()) {
        val width = size.width
        val height = size.height
        val centerX = width / 2
        val centerY = height / 2

        // Colors
        val eyeColor = Color(0xFF00FFFF) // Cyan
        val mouthColor = Color(0xFF00FFFF)
        val eyebrowColor = Color(0xFF00FFFF)

        // Eyes config
        val eyeRadius = width * 0.1f
        val eyeOffsetX = width * 0.2f
        val eyeY = centerY - (height * 0.1f)

        if (!isBlinking) {
            // Left Eye Ring
            drawCircle(
                color = eyeColor,
                radius = eyeRadius,
                center = Offset(centerX - eyeOffsetX, eyeY),
                style = Stroke(width = 10f)
            )
            // Right Eye Ring
            drawCircle(
                color = eyeColor,
                radius = eyeRadius,
                center = Offset(centerX + eyeOffsetX, eyeY),
                style = Stroke(width = 10f)
            )
            // Pupils
            drawCircle(
                color = eyeColor,
                radius = eyeRadius * 0.3f,
                center = Offset(centerX - eyeOffsetX + pupilOffset.value.x, eyeY + pupilOffset.value.y)
            )
             drawCircle(
                color = eyeColor,
                radius = eyeRadius * 0.3f,
                center = Offset(centerX + eyeOffsetX + pupilOffset.value.x, eyeY + pupilOffset.value.y)
            )

        } else {
            // Blink (flat lines)
            drawLine(
                color = eyeColor,
                start = Offset(centerX - eyeOffsetX - eyeRadius, eyeY),
                end = Offset(centerX - eyeOffsetX + eyeRadius, eyeY),
                strokeWidth = 10f,
                cap = StrokeCap.Round
            )
            drawLine(
                color = eyeColor,
                start = Offset(centerX + eyeOffsetX - eyeRadius, eyeY),
                end = Offset(centerX + eyeOffsetX + eyeRadius, eyeY),
                strokeWidth = 10f,
                cap = StrokeCap.Round
            )
        }

        // Eyebrows
        val eyebrowWidth = eyeRadius * 1.8f // Make them wider
        val eyebrowStrokeWidth = 10f
        val eyebrowBaseY = eyeY - eyeRadius - (height * 0.08f) // Higher
        val eyebrowControlPointOffset = eyebrowAnimationProgress * (height * 0.03f) // More pronounced bend

        // Left Eyebrow
        val leftEyebrowPath = Path().apply {
            moveTo(centerX - eyeOffsetX - eyebrowWidth / 2, eyebrowBaseY)
            quadraticBezierTo(
                centerX - eyeOffsetX,
                eyebrowBaseY - eyebrowControlPointOffset, // Control point moves up
                centerX - eyeOffsetX + eyebrowWidth / 2,
                eyebrowBaseY
            )
        }
        drawPath(leftEyebrowPath, color = eyebrowColor, style = Stroke(width = eyebrowStrokeWidth, cap = StrokeCap.Round))

        // Right Eyebrow
        val rightEyebrowPath = Path().apply {
            moveTo(centerX + eyeOffsetX - eyebrowWidth / 2, eyebrowBaseY)
            quadraticBezierTo(
                centerX + eyeOffsetX,
                eyebrowBaseY - eyebrowControlPointOffset, // Control point moves up
                centerX + eyeOffsetX + eyebrowWidth / 2,
                eyebrowBaseY
            )
        }
        drawPath(rightEyebrowPath, color = eyebrowColor, style = Stroke(width = eyebrowStrokeWidth, cap = StrokeCap.Round))


        // Mouth
        val maxAmp = 20000f
        val normalizedAmp = (amplitude.coerceAtMost(maxAmp.toInt()) / maxAmp).coerceIn(0f, 1f)
        
        val mouthBaseY = centerY + (height * 0.25f)
        
        // Make width dynamic with amplitude
        val minMouthWidth = width * 0.25f
        val maxMouthWidth = width * 0.45f
        val currentMouthWidth = minMouthWidth + ((maxMouthWidth - minMouthWidth) * normalizedAmp)

        // Make height dynamic with amplitude
        val minMouthHeight = 15f
        val maxMouthOpenHeight = height * 0.2f
        val currentMouthHeight = minMouthHeight + (maxMouthOpenHeight * normalizedAmp)

        // Draw mouth outline as an oval
        drawOval(
            color = mouthColor,
            topLeft = Offset(centerX - (currentMouthWidth / 2), mouthBaseY - (currentMouthHeight / 2)),
            size = Size(currentMouthWidth, currentMouthHeight),
            style = Stroke(width = 8f)
        )
        
        // Draw mouth fill as an oval
        if (normalizedAmp > 0.05f) { // Only fill if speaking
             drawOval(
                color = mouthColor.copy(alpha = 0.5f * normalizedAmp),
                topLeft = Offset(centerX - (currentMouthWidth / 2), mouthBaseY - (currentMouthHeight / 2)),
                size = Size(currentMouthWidth, currentMouthHeight)
            )
        }
    }
}

package com.opendroids.tourbot.ui.components

import androidx.compose.animation.core.*
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
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

    LaunchedEffect(Unit) {
        while (true) {
            // Blink every 2-5 seconds
            delay(Random.nextLong(2000, 5000))
            isBlinking = true
            delay(150)
            isBlinking = false
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
                center = Offset(centerX - eyeOffsetX, eyeY)
            )
             drawCircle(
                color = eyeColor,
                radius = eyeRadius * 0.3f,
                center = Offset(centerX + eyeOffsetX, eyeY)
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
        
        val mouthWidth = width * 0.33f // Approximately 2/3rds of previous width (0.5 * 2/3 = 0.33)
        val mouthBaseY = centerY + (height * 0.25f)
        val maxMouthOpenHeight = height * 0.2f // Still allows for a full opening
        
        val currentMouthHeight = 15f + (maxMouthOpenHeight * normalizedAmp) // Min height for closed mouth

        // Draw mouth outline as an oval
        drawOval(
            color = mouthColor,
            topLeft = Offset(centerX - (mouthWidth / 2), mouthBaseY - (currentMouthHeight / 2)),
            size = Size(mouthWidth, currentMouthHeight),
            style = Stroke(width = 8f)
        )
        
        // Draw mouth fill as an oval
        if (normalizedAmp > 0.05f) { // Only fill if speaking
             drawOval(
                color = mouthColor.copy(alpha = 0.5f * normalizedAmp),
                topLeft = Offset(centerX - (mouthWidth / 2) + 10, mouthBaseY - (currentMouthHeight / 2) + 10),
                size = Size(mouthWidth - 20, currentMouthHeight - 20)
            )
        }
    }
}
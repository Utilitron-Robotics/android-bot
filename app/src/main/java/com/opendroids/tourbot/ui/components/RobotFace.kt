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
import kotlin.math.exp
import kotlin.math.pow
import kotlin.math.sin
import kotlin.random.Random

@Composable
fun RobotFace(
    amplitude: Int,
    modifier: Modifier = Modifier
) {
    var isBlinking by remember { mutableStateOf(false) }
    val pupilOffset = remember { Animatable(Offset.Zero, Offset.VectorConverter) }

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
            delay(Random.nextLong(1500, 4000))
            val maxX = 15f
            val maxY = 10f
            pupilOffset.animateTo(
                targetValue = Offset(
                    x = Random.nextFloat() * 2 * maxX - maxX,
                    y = Random.nextFloat() * 2 * maxY - maxY
                ),
                animationSpec = tween(durationMillis = 500, easing = EaseInOut)
            )
            delay(1000)
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

    // Time-based animation for 'liveness'
    val time by rememberInfiniteTransition(label = "time").animateFloat(
        initialValue = 0f,
        targetValue = (2 * Math.PI).toFloat(),
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 1800, easing = LinearEasing),
            repeatMode = RepeatMode.Restart
        ), label = "time"
    )

    Canvas(modifier = modifier.fillMaxSize()) {
        val width = size.width
        val height = size.height
        val centerX = width / 2
        val centerY = height / 2

        // Colors
        val headColor = Color(0xFF222222) // Dark Charcoal
        val eyeColor = Color(0xFF00FFFF) // Cyan
        val mouthColor = Color(0xFF00FFFF)
        val eyebrowColor = Color(0xFF00FFFF)

        // Draw Head
        drawRoundRect(
            color = headColor,
            topLeft = Offset(centerX - width * 0.4f, centerY - height * 0.45f),
            size = Size(width * 0.8f, height * 0.9f),
            cornerRadius = CornerRadius(100f, 100f)
        )

        val eyeRadius = width * 0.1f
        val eyeOffsetX = width * 0.2f
        val eyeY = centerY - (height * 0.1f)

        if (!isBlinking) {
            drawCircle(color = eyeColor, radius = eyeRadius, center = Offset(centerX - eyeOffsetX, eyeY), style = Stroke(width = 10f))
            drawCircle(color = eyeColor, radius = eyeRadius, center = Offset(centerX + eyeOffsetX, eyeY), style = Stroke(width = 10f))
            drawCircle(color = eyeColor, radius = eyeRadius * 0.3f, center = Offset(centerX - eyeOffsetX + pupilOffset.value.x, eyeY + pupilOffset.value.y))
            drawCircle(color = eyeColor, radius = eyeRadius * 0.3f, center = Offset(centerX + eyeOffsetX + pupilOffset.value.x, eyeY + pupilOffset.value.y))
        } else {
            drawLine(color = eyeColor, start = Offset(centerX - eyeOffsetX - eyeRadius, eyeY), end = Offset(centerX - eyeOffsetX + eyeRadius, eyeY), strokeWidth = 10f, cap = StrokeCap.Round)
            drawLine(color = eyeColor, start = Offset(centerX + eyeOffsetX - eyeRadius, eyeY), end = Offset(centerX + eyeOffsetX + eyeRadius, eyeY), strokeWidth = 10f, cap = StrokeCap.Round)
        }

        val eyebrowWidth = eyeRadius * 1.8f
        val eyebrowStrokeWidth = 10f
        val eyebrowBaseY = eyeY - eyeRadius - (height * 0.08f)
        val eyebrowControlPointOffset = eyebrowAnimationProgress * (height * 0.03f)

        val leftEyebrowPath = Path().apply {
            moveTo(centerX - eyeOffsetX - eyebrowWidth / 2, eyebrowBaseY)
            quadraticBezierTo(centerX - eyeOffsetX, eyebrowBaseY - eyebrowControlPointOffset, centerX - eyeOffsetX + eyebrowWidth / 2, eyebrowBaseY)
        }
        drawPath(leftEyebrowPath, color = eyebrowColor, style = Stroke(width = eyebrowStrokeWidth, cap = StrokeCap.Round))

        val rightEyebrowPath = Path().apply {
            moveTo(centerX + eyeOffsetX - eyebrowWidth / 2, eyebrowBaseY)
            quadraticBezierTo(centerX + eyeOffsetX, eyebrowBaseY - eyebrowControlPointOffset, centerX + eyeOffsetX + eyebrowWidth / 2, eyebrowBaseY)
        }
        drawPath(rightEyebrowPath, color = eyebrowColor, style = Stroke(width = eyebrowStrokeWidth, cap = StrokeCap.Round))

        // Final Mouth: Central Spike with Dead Zone
        val maxAmp = 15000f
        var normalizedAmp = (amplitude / maxAmp).coerceIn(0f, 1f)

        // Dead zone for silence
        if (normalizedAmp < 0.05f) {
            normalizedAmp = 0f
        }

        val mouthBaseY = centerY + (height * 0.35f)
        val mouthWidth = width * 0.5f
        val maxMouthHeight = height * 0.25f
        val minMouthOpening = 4f

        val mouthPath = Path()
        val startX = centerX - mouthWidth / 2

        mouthPath.moveTo(startX, mouthBaseY)

        val segments = 100

        // Draw upper path
        for (i in 0..segments) {
            val progress = i.toFloat() / segments
            val x = startX + progress * mouthWidth

            val centralSpikeShape = exp(-(progress - 0.5f).pow(2) * 40f)
            val sideFuzz = sin(progress * 50f + time) * 0.15f
            
            val combinedEffect = (sideFuzz * (1 - centralSpikeShape)) + (centralSpikeShape * 3f)

            val yOffset = minMouthOpening + (combinedEffect * maxMouthHeight * normalizedAmp)
            mouthPath.lineTo(x, mouthBaseY - yOffset)
        }

        // Draw lower path in reverse
        for (i in segments downTo 0) {
            val progress = i.toFloat() / segments
            val x = startX + progress * mouthWidth

            val centralSpikeShape = exp(-(progress - 0.5f).pow(2) * 40f)
            val sideFuzz = sin(progress * 50f + time) * 0.15f
            val combinedEffect = (sideFuzz * (1 - centralSpikeShape)) + (centralSpikeShape * 3f)

            val yOffset = minMouthOpening + (combinedEffect * maxMouthHeight * normalizedAmp)
            mouthPath.lineTo(x, mouthBaseY + yOffset)
        }
        mouthPath.close()

        // Draw and fill
        val fillColor = if (normalizedAmp > 0) mouthColor.copy(alpha = 0.7f * normalizedAmp) else Color.Transparent
        drawPath(path = mouthPath, color = fillColor)
        drawPath(path = mouthPath, color = mouthColor, style = Stroke(width = 8f, cap = StrokeCap.Round))
    }
}

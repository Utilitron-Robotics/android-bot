package com.utilitron.robotrelay.ui

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.util.AttributeSet
import android.view.MotionEvent
import android.view.View
import com.utilitron.robotrelay.R
import kotlin.math.atan2
import kotlin.math.min
import kotlin.math.sqrt

/**
 * Circular joystick control for robot movement
 * Returns normalized X/Y values (-1.0 to 1.0)
 */
class JoystickView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : View(context, attrs, defStyleAttr) {

    // Paints
    private val basePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0xFF2A3F5F.toInt() // Dark blue-gray
        style = Paint.Style.FILL
    }

    private val baseStrokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0xFF4A6F9F.toInt() // Lighter blue
        style = Paint.Style.STROKE
        strokeWidth = 4f
    }

    private val stickPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0xFF6699CC.toInt() // Blue
        style = Paint.Style.FILL
    }

    private val stickStrokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0xFF88BBEE.toInt() // Light blue
        style = Paint.Style.STROKE
        strokeWidth = 3f
    }

    // Joystick state
    private var centerX = 0f
    private var centerY = 0f
    private var baseRadius = 0f
    private var stickRadius = 0f
    private var stickX = 0f
    private var stickY = 0f

    // Current position (-1.0 to 1.0)
    private var currentX = 0f
    private var currentY = 0f

    // Logo bitmap
    private var logoBitmap: Bitmap? = null

    // Listener
    var onMoveListener: ((x: Float, y: Float) -> Unit)? = null

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        centerX = w / 2f
        centerY = h / 2f
        baseRadius = min(w, h) / 2f - 20f
        stickRadius = baseRadius * 0.35f
        resetStick()

        // Load logo bitmap
        logoBitmap = BitmapFactory.decodeResource(resources, R.drawable.frontiertowerlogo)
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)

        // Draw base circle
        canvas.drawCircle(centerX, centerY, baseRadius, basePaint)
        canvas.drawCircle(centerX, centerY, baseRadius, baseStrokePaint)

        // Draw crosshair guides (optional)
        val guideLength = baseRadius * 0.3f
        val guidePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = 0x33FFFFFF
            strokeWidth = 2f
        }
        // Vertical
        canvas.drawLine(centerX, centerY - guideLength, centerX, centerY + guideLength, guidePaint)
        // Horizontal
        canvas.drawLine(centerX - guideLength, centerY, centerX + guideLength, centerY, guidePaint)

        // Draw stick
        canvas.drawCircle(stickX, stickY, stickRadius, stickPaint)
        canvas.drawCircle(stickX, stickY, stickRadius, stickStrokePaint)

        // Draw logo on stick (moves with stick)
        logoBitmap?.let { logo ->
            val logoSize = stickRadius * 1.5f
            val left = stickX - logoSize / 2
            val top = stickY - logoSize / 2
            val rect = RectF(left, top, left + logoSize, top + logoSize)
            canvas.drawBitmap(logo, null, rect, null)
        }
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        when (event.action) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_MOVE -> {
                updateStickPosition(event.x, event.y)
                return true
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                resetStick()
                return true
            }
        }
        return super.onTouchEvent(event)
    }

    private fun updateStickPosition(touchX: Float, touchY: Float) {
        val deltaX = touchX - centerX
        val deltaY = touchY - centerY
        val distance = sqrt(deltaX * deltaX + deltaY * deltaY)

        // Constrain stick to base circle
        val maxDistance = baseRadius - stickRadius
        if (distance > maxDistance) {
            val angle = atan2(deltaY, deltaX)
            stickX = centerX + maxDistance * kotlin.math.cos(angle)
            stickY = centerY + maxDistance * kotlin.math.sin(angle)
        } else {
            stickX = touchX
            stickY = touchY
        }

        // Calculate normalized position (-1.0 to 1.0)
        currentX = (stickX - centerX) / maxDistance
        currentY = (stickY - centerY) / maxDistance

        invalidate()
        onMoveListener?.invoke(currentX, currentY)
    }

    private fun resetStick() {
        stickX = centerX
        stickY = centerY
        currentX = 0f
        currentY = 0f
        invalidate()
        onMoveListener?.invoke(0f, 0f)
    }
}

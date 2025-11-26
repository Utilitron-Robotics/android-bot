package com.opendroids.tourbot.ui.components.pointcloud

import android.opengl.GLES20
import android.opengl.GLSurfaceView
import android.opengl.Matrix
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10
import kotlin.math.*

/**
 * OpenGL ES 2.0 renderer for point cloud face animation.
 * Renders thousands of particles that swirl and coalesce into a female face.
 */
class PointCloudRenderer : GLSurfaceView.Renderer {

    // Animation state
    enum class AnimationState {
        SWIRLING,       // Idle swirling globe (not speaking)
        COALESCING,     // Transitioning to face (starting to speak)
        SPEAKING,       // Face formed, mouth animating
        DISSOLVING      // Transitioning back to swirl (stopped speaking)
    }

    private var animationState = AnimationState.SWIRLING
    private var coalescenceProgress = 0f  // 0 = full swirl, 1 = full face
    private var timeElapsed = 0f
    private var lastFrameTime = System.nanoTime()

    // Audio amplitude (0-1 normalized)
    @Volatile
    var amplitude: Float = 0f

    // Speaking detection with hysteresis
    private var isSpeaking = false
    private var silenceTimer = 0f
    private val silenceThreshold = 0.5f  // Seconds of silence before dissolving
    private val speakingThreshold = 0.05f  // Amplitude threshold to detect speech

    // Point cloud data
    private lateinit var facePoints: List<FaceGeometry.FacePoint>
    private lateinit var spherePoints: List<FloatArray>
    private var pointCount = 0

    // OpenGL buffers
    private var vertexBuffer: FloatBuffer? = null
    private var colorBuffer: FloatBuffer? = null
    private var sizeBuffer: FloatBuffer? = null

    // Shader program
    private var shaderProgram = 0

    // Matrices
    private val mvpMatrix = FloatArray(16)
    private val projectionMatrix = FloatArray(16)
    private val viewMatrix = FloatArray(16)
    private val modelMatrix = FloatArray(16)

    // Animation parameters
    private var globalRotation = 0f
    private var breathingPhase = 0f
    private var blinkTimer = 0f
    private var nextBlinkTime = 3f
    private var isBlinking = false
    private var eyeLookX = 0f
    private var eyeLookY = 0f
    private var eyeLookTarget = floatArrayOf(0f, 0f)
    private var nextEyeMoveTime = 2f

    // Mouth animation
    private var mouthOpenAmount = 0f
    private var targetMouthOpen = 0f

    // Colors
    private val primaryColor = floatArrayOf(0f, 1f, 1f, 1f)      // Cyan
    private val secondaryColor = floatArrayOf(0f, 0.8f, 1f, 1f)  // Light blue
    private val accentColor = floatArrayOf(1f, 0f, 0.8f, 1f)     // Magenta accent

    companion object {
        private const val COORDS_PER_VERTEX = 3
        private const val POINT_COUNT = 3000

        private const val VERTEX_SHADER = """
            uniform mat4 uMVPMatrix;
            attribute vec4 aPosition;
            attribute vec4 aColor;
            attribute float aPointSize;
            varying vec4 vColor;

            void main() {
                gl_Position = uMVPMatrix * aPosition;
                gl_PointSize = aPointSize;
                vColor = aColor;
            }
        """

        private const val FRAGMENT_SHADER = """
            precision mediump float;
            varying vec4 vColor;

            void main() {
                // Create soft circular points with glow
                vec2 coord = gl_PointCoord - vec2(0.5);
                float dist = length(coord);

                // Soft falloff
                float alpha = 1.0 - smoothstep(0.3, 0.5, dist);

                // Glow effect
                float glow = exp(-dist * 4.0) * 0.5;

                gl_FragColor = vec4(vColor.rgb, vColor.a * (alpha + glow));
            }
        """
    }

    override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
        GLES20.glClearColor(0.02f, 0.02f, 0.05f, 1f)
        GLES20.glEnable(GLES20.GL_BLEND)
        GLES20.glBlendFunc(GLES20.GL_SRC_ALPHA, GLES20.GL_ONE)

        // Enable point sprites
        GLES20.glEnable(0x8861) // GL_POINT_SPRITE_OES
        GLES20.glEnable(0x8642) // GL_VERTEX_PROGRAM_POINT_SIZE

        // Initialize geometry
        initializeGeometry()

        // Create shader program
        shaderProgram = createShaderProgram()
    }

    private fun initializeGeometry() {
        facePoints = FaceGeometry.generateFacePoints(POINT_COUNT)
        spherePoints = FaceGeometry.generateSpherePoints(POINT_COUNT)
        pointCount = POINT_COUNT

        // Allocate buffers
        vertexBuffer = ByteBuffer.allocateDirect(pointCount * COORDS_PER_VERTEX * 4)
            .order(ByteOrder.nativeOrder())
            .asFloatBuffer()

        colorBuffer = ByteBuffer.allocateDirect(pointCount * 4 * 4)
            .order(ByteOrder.nativeOrder())
            .asFloatBuffer()

        sizeBuffer = ByteBuffer.allocateDirect(pointCount * 4)
            .order(ByteOrder.nativeOrder())
            .asFloatBuffer()
    }

    override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
        GLES20.glViewport(0, 0, width, height)

        val ratio = width.toFloat() / height.toFloat()
        Matrix.frustumM(projectionMatrix, 0, -ratio, ratio, -1f, 1f, 2f, 10f)

        Matrix.setLookAtM(
            viewMatrix, 0,
            0f, 0f, 4f,   // Eye position
            0f, 0f, 0f,   // Look at
            0f, 1f, 0f    // Up vector
        )
    }

    override fun onDrawFrame(gl: GL10?) {
        val currentTime = System.nanoTime()
        val deltaTime = (currentTime - lastFrameTime) / 1_000_000_000f
        lastFrameTime = currentTime
        timeElapsed += deltaTime

        // Update animation state
        updateAnimation(deltaTime)

        // Clear screen
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT or GLES20.GL_DEPTH_BUFFER_BIT)

        // Update point positions based on animation state
        updatePointPositions()

        // Set up matrices
        Matrix.setIdentityM(modelMatrix, 0)

        // Global rotation for swirl effect
        if (animationState == AnimationState.SWIRLING || coalescenceProgress < 1f) {
            Matrix.rotateM(modelMatrix, 0, globalRotation, 0f, 1f, 0.2f)
        }

        // Breathing animation when face is formed
        if (coalescenceProgress > 0.5f) {
            val breathScale = 1f + sin(breathingPhase) * 0.01f * coalescenceProgress
            Matrix.scaleM(modelMatrix, 0, breathScale, breathScale, breathScale)
        }

        Matrix.multiplyMM(mvpMatrix, 0, viewMatrix, 0, modelMatrix, 0)
        Matrix.multiplyMM(mvpMatrix, 0, projectionMatrix, 0, mvpMatrix, 0)

        // Render points
        renderPoints()
    }

    private fun updateAnimation(deltaTime: Float) {
        // Detect speaking state with hysteresis to avoid flickering
        val currentlySpeaking = amplitude > speakingThreshold
        if (currentlySpeaking) {
            isSpeaking = true
            silenceTimer = 0f
        } else if (isSpeaking) {
            silenceTimer += deltaTime
            if (silenceTimer > silenceThreshold) {
                isSpeaking = false
            }
        }

        // State machine for animation - driven by speech
        when (animationState) {
            AnimationState.SWIRLING -> {
                // Fast swirling globe
                globalRotation += deltaTime * 60f
                // Transition to coalescing when speaking starts
                if (isSpeaking) {
                    animationState = AnimationState.COALESCING
                }
            }
            AnimationState.COALESCING -> {
                // Slow down rotation as face forms
                globalRotation += deltaTime * 60f * (1f - coalescenceProgress)
                // Fast coalescence (0.8 seconds to form face)
                coalescenceProgress = (coalescenceProgress + deltaTime * 1.25f).coerceAtMost(1f)
                if (coalescenceProgress >= 1f) {
                    animationState = AnimationState.SPEAKING
                }
                // If speaking stops during coalescence, still complete the formation
            }
            AnimationState.SPEAKING -> {
                // Very subtle rotation while speaking
                globalRotation += deltaTime * 2f
                // Transition to dissolving when speaking stops
                if (!isSpeaking) {
                    animationState = AnimationState.DISSOLVING
                }
            }
            AnimationState.DISSOLVING -> {
                // Speed up rotation as face dissolves
                globalRotation += deltaTime * 60f * (1f - coalescenceProgress)
                // Dissolve back to swirl (1.2 seconds)
                coalescenceProgress = (coalescenceProgress - deltaTime * 0.83f).coerceAtLeast(0f)
                if (coalescenceProgress <= 0f) {
                    animationState = AnimationState.SWIRLING
                }
                // If speaking starts again during dissolve, go back to coalescing
                if (isSpeaking) {
                    animationState = AnimationState.COALESCING
                }
            }
        }

        // Update breathing (only when face is formed)
        if (coalescenceProgress > 0.5f) {
            breathingPhase += deltaTime * 1.5f
        }

        // Update blinking (only when face is mostly formed)
        if (coalescenceProgress > 0.8f) {
            blinkTimer += deltaTime
            if (blinkTimer > nextBlinkTime) {
                isBlinking = true
                blinkTimer = 0f
                nextBlinkTime = 2f + (Math.random() * 4f).toFloat()
            }
            if (isBlinking && blinkTimer > 0.15f) {
                isBlinking = false
            }
        } else {
            isBlinking = false
        }

        // Update eye movement (only when face is formed)
        if (coalescenceProgress > 0.9f) {
            if (timeElapsed > nextEyeMoveTime) {
                eyeLookTarget[0] = ((Math.random() * 2 - 1) * 0.03f).toFloat()
                eyeLookTarget[1] = ((Math.random() * 2 - 1) * 0.02f).toFloat()
                nextEyeMoveTime = timeElapsed + 1.5f + (Math.random() * 3f).toFloat()
            }
            eyeLookX += (eyeLookTarget[0] - eyeLookX) * deltaTime * 3f
            eyeLookY += (eyeLookTarget[1] - eyeLookY) * deltaTime * 3f
        } else {
            eyeLookX = 0f
            eyeLookY = 0f
        }

        // Update mouth based on amplitude
        targetMouthOpen = amplitude
        mouthOpenAmount += (targetMouthOpen - mouthOpenAmount) * deltaTime * 15f
    }

    private fun updatePointPositions() {
        vertexBuffer?.clear()
        colorBuffer?.clear()
        sizeBuffer?.clear()

        for (i in 0 until pointCount) {
            val facePoint = facePoints[i]
            val spherePoint = spherePoints[i]

            // Interpolate between sphere and face position
            var x: Float
            var y: Float
            var z: Float

            if (coalescenceProgress < 1f) {
                // Swirling sphere to face transition
                val t = easeInOutCubic(coalescenceProgress)

                // Add spiral motion during transition
                val spiralAngle = timeElapsed * 2f + i * 0.01f
                val spiralRadius = 0.3f * (1f - t)
                val spiralX = cos(spiralAngle) * spiralRadius
                val spiralZ = sin(spiralAngle) * spiralRadius

                x = lerp(spherePoint[0] + spiralX, facePoint.x, t)
                y = lerp(spherePoint[1], facePoint.y, t)
                z = lerp(spherePoint[2] + spiralZ, facePoint.z, t)
            } else {
                x = facePoint.x
                y = facePoint.y
                z = facePoint.z

                // Apply face animations
                when (facePoint.region) {
                    FaceGeometry.FaceRegion.LEFT_EYE, FaceGeometry.FaceRegion.RIGHT_EYE -> {
                        // Blinking - flatten eyes
                        if (isBlinking) {
                            y = facePoint.y * 0.1f + 0.15f * 0.9f
                        }
                        // Eye look offset
                        x += eyeLookX
                        y += eyeLookY
                    }
                    FaceGeometry.FaceRegion.UPPER_LIP -> {
                        // Mouth opening - move upper lip up significantly
                        y += mouthOpenAmount * 0.15f
                        z += mouthOpenAmount * 0.05f
                    }
                    FaceGeometry.FaceRegion.LOWER_LIP -> {
                        // Mouth opening - move lower lip down significantly
                        y -= mouthOpenAmount * 0.25f
                        z += mouthOpenAmount * 0.08f
                    }
                    FaceGeometry.FaceRegion.LEFT_EYEBROW, FaceGeometry.FaceRegion.RIGHT_EYEBROW -> {
                        // Eyebrow raise when speaking
                        y += mouthOpenAmount * 0.04f
                    }
                    else -> {}
                }

                // Add subtle particle drift for organic feel
                val drift = sin(timeElapsed * 2f + i * 0.1f) * 0.005f
                x += drift
                y += cos(timeElapsed * 1.5f + i * 0.15f) * 0.003f
            }

            vertexBuffer?.put(x)
            vertexBuffer?.put(y)
            vertexBuffer?.put(z)

            // Calculate color based on region and state
            val color = calculatePointColor(facePoint, i)
            colorBuffer?.put(color[0])
            colorBuffer?.put(color[1])
            colorBuffer?.put(color[2])
            colorBuffer?.put(color[3])

            // Calculate point size
            val size = calculatePointSize(facePoint, i)
            sizeBuffer?.put(size)
        }

        vertexBuffer?.position(0)
        colorBuffer?.position(0)
        sizeBuffer?.position(0)
    }

    private fun calculatePointColor(point: FaceGeometry.FacePoint, index: Int): FloatArray {
        val baseColor = when (point.region) {
            FaceGeometry.FaceRegion.LEFT_EYE, FaceGeometry.FaceRegion.RIGHT_EYE -> {
                if (isBlinking) floatArrayOf(0f, 0.5f, 0.5f, 0.3f)
                else floatArrayOf(0f, 1f, 1f, 1f * point.intensity)
            }
            FaceGeometry.FaceRegion.UPPER_LIP, FaceGeometry.FaceRegion.LOWER_LIP -> {
                // Lips glow brightly when speaking
                val speakGlow = mouthOpenAmount * 0.5f
                floatArrayOf(0.4f + speakGlow, 0.9f, 1f, 1f)
            }
            FaceGeometry.FaceRegion.LEFT_EYEBROW, FaceGeometry.FaceRegion.RIGHT_EYEBROW -> {
                floatArrayOf(0f, 0.9f, 0.9f, 0.85f)
            }
            FaceGeometry.FaceRegion.NOSE -> {
                floatArrayOf(0f, 0.85f, 0.95f, 0.7f * point.intensity)
            }
            FaceGeometry.FaceRegion.FACE_OUTLINE -> {
                floatArrayOf(0f, 0.7f, 0.9f, 0.6f * point.intensity)
            }
            else -> {
                floatArrayOf(0f, 0.6f, 0.8f, 0.4f * point.intensity)
            }
        }

        // Add shimmer effect
        val shimmer = (sin(timeElapsed * 3f + index * 0.05f) * 0.5f + 0.5f) * 0.2f
        baseColor[0] = (baseColor[0] + shimmer).coerceAtMost(1f)
        baseColor[1] = (baseColor[1] + shimmer * 0.5f).coerceAtMost(1f)

        // During swirling, use more varied colors
        if (coalescenceProgress < 1f) {
            val variety = 1f - coalescenceProgress
            val hueShift = sin(index * 0.1f + timeElapsed) * variety
            baseColor[0] = (baseColor[0] + hueShift * 0.3f).coerceIn(0f, 1f)
            baseColor[2] = (baseColor[2] + hueShift * 0.2f).coerceIn(0f, 1f)
        }

        return baseColor
    }

    private fun calculatePointSize(point: FaceGeometry.FacePoint, index: Int): Float {
        var size = when (point.region) {
            FaceGeometry.FaceRegion.LEFT_EYE, FaceGeometry.FaceRegion.RIGHT_EYE -> {
                if (isBlinking) 2f else 8f * point.intensity
            }
            FaceGeometry.FaceRegion.UPPER_LIP, FaceGeometry.FaceRegion.LOWER_LIP -> {
                // Lips get bigger when mouth opens
                8f + mouthOpenAmount * 6f
            }
            FaceGeometry.FaceRegion.LEFT_EYEBROW, FaceGeometry.FaceRegion.RIGHT_EYEBROW -> 5f
            FaceGeometry.FaceRegion.NOSE -> 5f * point.intensity
            FaceGeometry.FaceRegion.FACE_OUTLINE -> 4f
            else -> 3f * point.intensity
        }

        // Pulsing effect
        val pulse = sin(timeElapsed * 4f + index * 0.02f) * 0.2f + 1f
        size *= pulse

        // Larger points during swirl for visibility
        if (coalescenceProgress < 1f) {
            size *= 1f + (1f - coalescenceProgress) * 0.5f
        }

        return size
    }

    private fun renderPoints() {
        GLES20.glUseProgram(shaderProgram)

        // Get attribute/uniform locations
        val positionHandle = GLES20.glGetAttribLocation(shaderProgram, "aPosition")
        val colorHandle = GLES20.glGetAttribLocation(shaderProgram, "aColor")
        val sizeHandle = GLES20.glGetAttribLocation(shaderProgram, "aPointSize")
        val mvpMatrixHandle = GLES20.glGetUniformLocation(shaderProgram, "uMVPMatrix")

        // Pass MVP matrix
        GLES20.glUniformMatrix4fv(mvpMatrixHandle, 1, false, mvpMatrix, 0)

        // Enable vertex arrays
        GLES20.glEnableVertexAttribArray(positionHandle)
        GLES20.glEnableVertexAttribArray(colorHandle)
        GLES20.glEnableVertexAttribArray(sizeHandle)

        // Set vertex data
        GLES20.glVertexAttribPointer(
            positionHandle, COORDS_PER_VERTEX,
            GLES20.GL_FLOAT, false,
            COORDS_PER_VERTEX * 4, vertexBuffer
        )

        GLES20.glVertexAttribPointer(
            colorHandle, 4,
            GLES20.GL_FLOAT, false,
            4 * 4, colorBuffer
        )

        GLES20.glVertexAttribPointer(
            sizeHandle, 1,
            GLES20.GL_FLOAT, false,
            4, sizeBuffer
        )

        // Draw points
        GLES20.glDrawArrays(GLES20.GL_POINTS, 0, pointCount)

        // Disable vertex arrays
        GLES20.glDisableVertexAttribArray(positionHandle)
        GLES20.glDisableVertexAttribArray(colorHandle)
        GLES20.glDisableVertexAttribArray(sizeHandle)
    }

    private fun createShaderProgram(): Int {
        val vertexShader = loadShader(GLES20.GL_VERTEX_SHADER, VERTEX_SHADER)
        val fragmentShader = loadShader(GLES20.GL_FRAGMENT_SHADER, FRAGMENT_SHADER)

        return GLES20.glCreateProgram().also { program ->
            GLES20.glAttachShader(program, vertexShader)
            GLES20.glAttachShader(program, fragmentShader)
            GLES20.glLinkProgram(program)
        }
    }

    private fun loadShader(type: Int, shaderCode: String): Int {
        return GLES20.glCreateShader(type).also { shader ->
            GLES20.glShaderSource(shader, shaderCode)
            GLES20.glCompileShader(shader)
        }
    }

    // Utility functions
    private fun lerp(a: Float, b: Float, t: Float): Float = a + (b - a) * t

    private fun easeInOutCubic(t: Float): Float {
        return if (t < 0.5f) {
            4f * t * t * t
        } else {
            1f - (-2f * t + 2f).pow(3) / 2f
        }
    }

    /**
     * Reset animation to swirling state (useful when restarting).
     */
    fun resetAnimation() {
        animationState = AnimationState.SWIRLING
        coalescenceProgress = 0f
        timeElapsed = 0f
        globalRotation = 0f
        isSpeaking = false
        silenceTimer = 0f
    }

    /**
     * Skip directly to face formed state (useful for testing).
     */
    fun skipToFace() {
        animationState = AnimationState.SPEAKING
        coalescenceProgress = 1f
        isSpeaking = true
    }
}

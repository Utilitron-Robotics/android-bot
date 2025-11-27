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
 * Renders a swirling globe of particles with a face that presses through
 * like a membrane/balloon effect when speaking.
 */
class PointCloudRenderer : GLSurfaceView.Renderer {

    // Audio amplitude (0-1 normalized)
    @Volatile
    var amplitude: Float = 0f

    // Speaking detection with hysteresis
    private var isSpeaking = false
    private var silenceTimer = 0f
    private val silenceThreshold = 0.4f
    private val speakingThreshold = 0.02f

    // Face impression strength (0 = no face, 1 = full face pushing through)
    private var faceImpressionStrength = 0f
    private var targetFaceStrength = 0f

    // Mouth animation
    private var mouthOpenAmount = 0f

    // Point cloud data
    private lateinit var spherePoints: List<FloatArray>  // Base sphere positions
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

    // Animation
    private var timeElapsed = 0f
    private var lastFrameTime = System.nanoTime()
    private var globalRotation = 0f

    companion object {
        private const val COORDS_PER_VERTEX = 3
        private const val POINT_COUNT = 4000  // More points for smoother surface

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
                vec2 coord = gl_PointCoord - vec2(0.5);
                float dist = length(coord);
                float alpha = 1.0 - smoothstep(0.3, 0.5, dist);
                float glow = exp(-dist * 4.0) * 0.5;
                gl_FragColor = vec4(vColor.rgb, vColor.a * (alpha + glow));
            }
        """
    }

    override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
        GLES20.glClearColor(0.02f, 0.02f, 0.05f, 1f)
        GLES20.glEnable(GLES20.GL_BLEND)
        GLES20.glBlendFunc(GLES20.GL_SRC_ALPHA, GLES20.GL_ONE)
        GLES20.glEnable(0x8861) // GL_POINT_SPRITE_OES
        GLES20.glEnable(0x8642) // GL_VERTEX_PROGRAM_POINT_SIZE

        initializeGeometry()
        shaderProgram = createShaderProgram()
    }

    private fun initializeGeometry() {
        // Generate evenly distributed sphere points (Fibonacci sphere)
        spherePoints = generateFibonacciSphere(POINT_COUNT)
        pointCount = POINT_COUNT

        vertexBuffer = ByteBuffer.allocateDirect(pointCount * COORDS_PER_VERTEX * 4)
            .order(ByteOrder.nativeOrder()).asFloatBuffer()
        colorBuffer = ByteBuffer.allocateDirect(pointCount * 4 * 4)
            .order(ByteOrder.nativeOrder()).asFloatBuffer()
        sizeBuffer = ByteBuffer.allocateDirect(pointCount * 4)
            .order(ByteOrder.nativeOrder()).asFloatBuffer()
    }

    private fun generateFibonacciSphere(count: Int): List<FloatArray> {
        val points = mutableListOf<FloatArray>()
        val goldenRatio = (1 + sqrt(5f)) / 2
        for (i in 0 until count) {
            val theta = 2 * PI.toFloat() * i / goldenRatio
            val phi = acos(1 - 2 * (i + 0.5f) / count)
            val x = sin(phi) * cos(theta)
            val y = cos(phi)  // Y is up
            val z = sin(phi) * sin(theta)
            points.add(floatArrayOf(x, y, z))
        }
        return points
    }

    override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
        GLES20.glViewport(0, 0, width, height)
        val ratio = width.toFloat() / height.toFloat()
        Matrix.frustumM(projectionMatrix, 0, -ratio, ratio, -1f, 1f, 2f, 10f)
        Matrix.setLookAtM(viewMatrix, 0, 0f, 0f, 3.5f, 0f, 0f, 0f, 0f, 1f, 0f)
    }

    override fun onDrawFrame(gl: GL10?) {
        val currentTime = System.nanoTime()
        val deltaTime = (currentTime - lastFrameTime) / 1_000_000_000f
        lastFrameTime = currentTime
        timeElapsed += deltaTime

        updateAnimation(deltaTime)

        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT or GLES20.GL_DEPTH_BUFFER_BIT)

        updatePointPositions()

        Matrix.setIdentityM(modelMatrix, 0)
        // Slow rotation - face stays mostly forward
        Matrix.rotateM(modelMatrix, 0, globalRotation, 0f, 1f, 0f)
        // Slight tilt for 3D feel
        Matrix.rotateM(modelMatrix, 0, sin(timeElapsed * 0.3f) * 5f, 1f, 0f, 0f)

        Matrix.multiplyMM(mvpMatrix, 0, viewMatrix, 0, modelMatrix, 0)
        Matrix.multiplyMM(mvpMatrix, 0, projectionMatrix, 0, mvpMatrix, 0)

        renderPoints()
    }

    private fun updateAnimation(deltaTime: Float) {
        // Speaking detection
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

        // Face impression target
        targetFaceStrength = if (isSpeaking) 1f else 0f

        // Smooth transition for face appearing/disappearing
        val transitionSpeed = if (isSpeaking) 3f else 2f  // Faster appear, slower disappear
        faceImpressionStrength += (targetFaceStrength - faceImpressionStrength) * deltaTime * transitionSpeed

        // Mouth animation
        val targetMouth = amplitude * 1.5f  // Amplify for visibility
        mouthOpenAmount += (targetMouth - mouthOpenAmount) * deltaTime * 12f

        // Slow continuous rotation
        globalRotation += deltaTime * 8f
    }

    private fun updatePointPositions() {
        vertexBuffer?.clear()
        colorBuffer?.clear()
        sizeBuffer?.clear()

        for (i in 0 until pointCount) {
            val basePoint = spherePoints[i]

            // Add swirling motion to base sphere
            val swirlSpeed = 0.5f
            val swirlAngle = timeElapsed * swirlSpeed + basePoint[1] * 2f  // Latitude-based swirl
            val swirlAmount = 0.1f * (1f - faceImpressionStrength * 0.5f)  // Less swirl when face shows

            // Base position with swirl
            var x = basePoint[0] + sin(swirlAngle + i * 0.1f) * swirlAmount * basePoint[2]
            var y = basePoint[1]
            var z = basePoint[2] + cos(swirlAngle + i * 0.1f) * swirlAmount * basePoint[0]

            // Normalize to keep on sphere surface
            val len = sqrt(x * x + y * y + z * z)
            x /= len
            y /= len
            z /= len

            // Calculate face displacement for this point
            // Face is on the +Z side of the sphere (front)
            val faceDisplacement = calculateFaceDisplacement(x, y, z)

            // Apply face impression - push points outward where face is
            val displacement = faceDisplacement * faceImpressionStrength
            x += x * displacement * 0.3f
            y += y * displacement * 0.3f
            z += z * displacement * 0.3f

            vertexBuffer?.put(x)
            vertexBuffer?.put(y)
            vertexBuffer?.put(z)

            // Color - brighter where face features are
            val color = calculatePointColor(x, y, z, faceDisplacement)
            colorBuffer?.put(color[0])
            colorBuffer?.put(color[1])
            colorBuffer?.put(color[2])
            colorBuffer?.put(color[3])

            // Size - larger for face features
            val size = calculatePointSize(faceDisplacement)
            sizeBuffer?.put(size)
        }

        vertexBuffer?.position(0)
        colorBuffer?.position(0)
        sizeBuffer?.position(0)
    }

    /**
     * Calculate how much the face pushes out at this point on the sphere.
     * Returns 0-1 where higher values = more protrusion.
     */
    private fun calculateFaceDisplacement(x: Float, y: Float, z: Float): Float {
        // Only affect front-facing points (positive Z)
        if (z < 0) return 0f

        // Project onto face plane (front of sphere)
        // Face is mapped to roughly -0.5 to 0.5 in X and Y
        val faceX = x / (z + 0.5f)  // Perspective projection
        val faceY = y / (z + 0.5f)

        // Check if within face bounds
        if (faceX.absoluteValue > 0.8f || faceY.absoluteValue > 1.0f) return 0f

        var displacement = 0f

        // Face oval base - slight overall protrusion
        val inFaceOval = (faceX / 0.6f).pow(2) + (faceY / 0.85f).pow(2) < 1f
        if (inFaceOval) {
            displacement = 0.3f * z  // Base face shape, stronger at front
        }

        // Nose - strongest protrusion
        val noseX = faceX.absoluteValue
        val noseY = faceY + 0.1f  // Nose is slightly below center
        if (noseX < 0.1f && noseY > -0.15f && noseY < 0.2f) {
            val noseFactor = (1f - noseX / 0.1f) * (1f - (noseY - 0.05f).absoluteValue / 0.2f)
            displacement = max(displacement, 0.8f * noseFactor * z)
        }

        // Brow ridge
        if (faceY > 0.25f && faceY < 0.45f && faceX.absoluteValue < 0.5f) {
            val browFactor = (1f - (faceY - 0.35f).absoluteValue / 0.1f).coerceIn(0f, 1f)
            displacement = max(displacement, 0.4f * browFactor * z)
        }

        // Cheekbones
        val cheekDist = sqrt((faceX.absoluteValue - 0.35f).pow(2) + (faceY + 0.05f).pow(2))
        if (cheekDist < 0.2f) {
            val cheekFactor = 1f - cheekDist / 0.2f
            displacement = max(displacement, 0.35f * cheekFactor * z)
        }

        // Lips - protrude and animate with speech
        val lipY = faceY + 0.45f  // Lips below center
        val lipX = faceX.absoluteValue
        if (lipX < 0.25f && lipY.absoluteValue < 0.15f) {
            val lipFactor = (1f - lipX / 0.25f) * (1f - lipY.absoluteValue / 0.15f)
            // Mouth opens - upper lip up, lower lip down
            val mouthOffset = if (lipY > 0) -mouthOpenAmount * 0.1f else mouthOpenAmount * 0.15f
            val adjustedLipY = lipY + mouthOffset
            if (adjustedLipY.absoluteValue < 0.15f) {
                displacement = max(displacement, 0.5f * lipFactor * z)
            }
        }

        // Eye sockets - slight INDENT (negative displacement)
        val leftEyeDist = sqrt((faceX + 0.25f).pow(2) + (faceY - 0.15f).pow(2))
        val rightEyeDist = sqrt((faceX - 0.25f).pow(2) + (faceY - 0.15f).pow(2))
        val eyeDist = min(leftEyeDist, rightEyeDist)
        if (eyeDist < 0.12f) {
            val eyeFactor = 1f - eyeDist / 0.12f
            displacement -= 0.15f * eyeFactor * z  // Indent for eyes
        }

        // Chin
        if (faceY < -0.6f && faceX.absoluteValue < 0.2f) {
            val chinFactor = (1f - (faceY + 0.7f).absoluteValue / 0.1f).coerceIn(0f, 1f)
            displacement = max(displacement, 0.3f * chinFactor * z)
        }

        return displacement.coerceIn(-0.2f, 1f)
    }

    private fun calculatePointColor(x: Float, y: Float, z: Float, displacement: Float): FloatArray {
        // Base swirling color
        val hue = (timeElapsed * 0.1f + y * 0.5f + x * 0.3f) % 1f

        // Cyan base with slight variation
        var r = 0f + hue * 0.1f
        var g = 0.7f + displacement * 0.3f
        var b = 0.9f + displacement * 0.1f
        var a = 0.6f + displacement * 0.4f

        // Face features glow brighter
        if (displacement > 0.3f && faceImpressionStrength > 0.5f) {
            r += 0.2f * displacement
            g = min(1f, g + 0.2f)
            a = min(1f, a + 0.2f)
        }

        // Eye areas glow cyan
        if (displacement < 0 && faceImpressionStrength > 0.5f) {
            g = 1f
            b = 1f
            a = 1f
        }

        // Add shimmer
        val shimmer = sin(timeElapsed * 3f + x * 10f + y * 10f) * 0.1f + 0.1f
        r += shimmer
        g += shimmer * 0.5f

        return floatArrayOf(r.coerceIn(0f, 1f), g.coerceIn(0f, 1f), b.coerceIn(0f, 1f), a.coerceIn(0f, 1f))
    }

    private fun calculatePointSize(displacement: Float): Float {
        var size = 4f + displacement * 4f  // Larger where face protrudes

        // Pulsing effect
        size *= 1f + sin(timeElapsed * 2f) * 0.1f

        // Smaller when no face
        size *= 0.7f + faceImpressionStrength * 0.3f

        return size.coerceIn(2f, 12f)
    }

    private fun renderPoints() {
        GLES20.glUseProgram(shaderProgram)

        val positionHandle = GLES20.glGetAttribLocation(shaderProgram, "aPosition")
        val colorHandle = GLES20.glGetAttribLocation(shaderProgram, "aColor")
        val sizeHandle = GLES20.glGetAttribLocation(shaderProgram, "aPointSize")
        val mvpMatrixHandle = GLES20.glGetUniformLocation(shaderProgram, "uMVPMatrix")

        GLES20.glUniformMatrix4fv(mvpMatrixHandle, 1, false, mvpMatrix, 0)

        GLES20.glEnableVertexAttribArray(positionHandle)
        GLES20.glEnableVertexAttribArray(colorHandle)
        GLES20.glEnableVertexAttribArray(sizeHandle)

        GLES20.glVertexAttribPointer(positionHandle, COORDS_PER_VERTEX, GLES20.GL_FLOAT, false, COORDS_PER_VERTEX * 4, vertexBuffer)
        GLES20.glVertexAttribPointer(colorHandle, 4, GLES20.GL_FLOAT, false, 4 * 4, colorBuffer)
        GLES20.glVertexAttribPointer(sizeHandle, 1, GLES20.GL_FLOAT, false, 4, sizeBuffer)

        GLES20.glDrawArrays(GLES20.GL_POINTS, 0, pointCount)

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

    fun resetAnimation() {
        faceImpressionStrength = 0f
        isSpeaking = false
        silenceTimer = 0f
    }

    fun skipToFace() {
        faceImpressionStrength = 1f
        isSpeaking = true
    }
}

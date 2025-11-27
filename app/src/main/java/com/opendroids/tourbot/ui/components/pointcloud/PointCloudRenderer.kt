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
import kotlin.random.Random

/**
 * Advanced point cloud renderer with real-time physics simulation
 * and viseme-based lip sync for speech animation.
 *
 * Physics: Verlet integration with curl noise turbulence
 * Lip Sync: Amplitude-driven viseme blending
 */
class PointCloudRenderer : GLSurfaceView.Renderer {

    // ========== Audio & Speech ==========
    @Volatile var amplitude: Float = 0f

    // Viseme system for lip sync
    enum class Viseme {
        NEUTRAL,    // Closed relaxed mouth
        AA,         // Open (ah, a)
        EE,         // Wide smile (ee, i)
        OO,         // Round pursed (oo, u, w)
        OH,         // Open round (oh, o)
        FV,         // Lower lip tucked (f, v)
        MBP,        // Lips pressed (m, b, p)
        TH,         // Tongue between teeth
        L           // Tongue up
    }

    private var currentViseme = Viseme.NEUTRAL
    private var targetViseme = Viseme.NEUTRAL
    private var visemeBlend = 0f
    private var visemeTimer = 0f
    private var lastAmplitude = 0f
    private var amplitudeVelocity = 0f  // For detecting sharp changes

    // Mouth shape parameters (interpolated)
    private var mouthOpenAmount = 0f
    private var mouthWideAmount = 0f   // Smile width
    private var mouthRoundAmount = 0f  // Pursed lips
    private var lipTuckAmount = 0f     // F/V sounds

    // ========== Physics Simulation ==========
    private lateinit var positions: FloatArray      // Current positions (x,y,z per point)
    private lateinit var prevPositions: FloatArray  // Previous positions for Verlet
    private lateinit var velocities: FloatArray     // For turbulence injection
    private lateinit var basePositions: FloatArray  // Rest positions on sphere
    private var pointCount = 0

    // Physics constants
    private val sphereRadius = 1.0f
    private val springStiffness = 15f      // Membrane tension
    private val damping = 0.97f            // Velocity damping
    private val turbulenceStrength = 0.3f
    private val noiseScale = 2.5f

    // ========== OpenGL ==========
    private var vertexBuffer: FloatBuffer? = null
    private var colorBuffer: FloatBuffer? = null
    private var sizeBuffer: FloatBuffer? = null
    private var shaderProgram = 0

    private val mvpMatrix = FloatArray(16)
    private val projectionMatrix = FloatArray(16)
    private val viewMatrix = FloatArray(16)
    private val modelMatrix = FloatArray(16)

    // ========== Animation State ==========
    private var timeElapsed = 0f
    private var lastFrameTime = System.nanoTime()
    private var globalRotation = 0f
    private var isSpeaking = false
    private var silenceTimer = 0f
    private var faceImpressionStrength = 0f

    // Curl noise offsets (for variation)
    private var noiseOffsetX = Random.nextFloat() * 1000f
    private var noiseOffsetY = Random.nextFloat() * 1000f
    private var noiseOffsetZ = Random.nextFloat() * 1000f

    companion object {
        private const val COORDS_PER_VERTEX = 3
        private const val POINT_COUNT = 4000
        private const val FIXED_TIMESTEP = 1f / 60f  // Physics at 60Hz

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
                float alpha = 1.0 - smoothstep(0.2, 0.5, dist);
                float glow = exp(-dist * 3.0) * 0.6;
                float core = exp(-dist * 8.0) * 0.4;
                gl_FragColor = vec4(vColor.rgb * (1.0 + core), vColor.a * (alpha + glow));
            }
        """
    }

    override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
        GLES20.glClearColor(0.01f, 0.01f, 0.03f, 1f)
        GLES20.glEnable(GLES20.GL_BLEND)
        GLES20.glBlendFunc(GLES20.GL_SRC_ALPHA, GLES20.GL_ONE)
        GLES20.glEnable(0x8861)
        GLES20.glEnable(0x8642)

        initializePhysics()
        shaderProgram = createShaderProgram()
    }

    private fun initializePhysics() {
        pointCount = POINT_COUNT
        positions = FloatArray(pointCount * 3)
        prevPositions = FloatArray(pointCount * 3)
        velocities = FloatArray(pointCount * 3)
        basePositions = FloatArray(pointCount * 3)

        // Generate Fibonacci sphere
        val goldenRatio = (1 + sqrt(5f)) / 2
        for (i in 0 until pointCount) {
            val theta = 2 * PI.toFloat() * i / goldenRatio
            val phi = acos(1 - 2 * (i + 0.5f) / pointCount)

            val x = sphereRadius * sin(phi) * cos(theta)
            val y = sphereRadius * cos(phi)
            val z = sphereRadius * sin(phi) * sin(theta)

            val idx = i * 3
            positions[idx] = x
            positions[idx + 1] = y
            positions[idx + 2] = z

            prevPositions[idx] = x
            prevPositions[idx + 1] = y
            prevPositions[idx + 2] = z

            basePositions[idx] = x
            basePositions[idx + 1] = y
            basePositions[idx + 2] = z

            velocities[idx] = 0f
            velocities[idx + 1] = 0f
            velocities[idx + 2] = 0f
        }

        vertexBuffer = ByteBuffer.allocateDirect(pointCount * COORDS_PER_VERTEX * 4)
            .order(ByteOrder.nativeOrder()).asFloatBuffer()
        colorBuffer = ByteBuffer.allocateDirect(pointCount * 4 * 4)
            .order(ByteOrder.nativeOrder()).asFloatBuffer()
        sizeBuffer = ByteBuffer.allocateDirect(pointCount * 4)
            .order(ByteOrder.nativeOrder()).asFloatBuffer()
    }

    override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
        GLES20.glViewport(0, 0, width, height)
        val ratio = width.toFloat() / height.toFloat()
        Matrix.frustumM(projectionMatrix, 0, -ratio, ratio, -1f, 1f, 2f, 10f)
        Matrix.setLookAtM(viewMatrix, 0, 0f, 0f, 3.2f, 0f, 0f, 0f, 0f, 1f, 0f)
    }

    override fun onDrawFrame(gl: GL10?) {
        val currentTime = System.nanoTime()
        val deltaTime = ((currentTime - lastFrameTime) / 1_000_000_000f).coerceAtMost(0.1f)
        lastFrameTime = currentTime
        timeElapsed += deltaTime

        // Update systems
        updateSpeechDetection(deltaTime)
        updateVisemes(deltaTime)
        updatePhysics(deltaTime)

        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT or GLES20.GL_DEPTH_BUFFER_BIT)

        updateBuffers()

        Matrix.setIdentityM(modelMatrix, 0)
        Matrix.rotateM(modelMatrix, 0, globalRotation, 0f, 1f, 0f)
        Matrix.rotateM(modelMatrix, 0, sin(timeElapsed * 0.2f) * 3f, 1f, 0f, 0f)

        Matrix.multiplyMM(mvpMatrix, 0, viewMatrix, 0, modelMatrix, 0)
        Matrix.multiplyMM(mvpMatrix, 0, projectionMatrix, 0, mvpMatrix, 0)

        renderPoints()
    }

    // ========== Speech & Viseme System ==========

    private fun updateSpeechDetection(deltaTime: Float) {
        val currentlySpeaking = amplitude > 0.02f

        if (currentlySpeaking) {
            isSpeaking = true
            silenceTimer = 0f
        } else if (isSpeaking) {
            silenceTimer += deltaTime
            if (silenceTimer > 0.4f) isSpeaking = false
        }

        // Face impression
        val targetStrength = if (isSpeaking) 1f else 0f
        val speed = if (isSpeaking) 4f else 2f
        faceImpressionStrength += (targetStrength - faceImpressionStrength) * deltaTime * speed

        // Slow rotation
        globalRotation += deltaTime * 6f

        // Track amplitude velocity for viseme detection
        amplitudeVelocity = (amplitude - lastAmplitude) / deltaTime.coerceAtLeast(0.001f)
        lastAmplitude = amplitude
    }

    private fun updateVisemes(deltaTime: Float) {
        visemeTimer += deltaTime

        // Determine target viseme based on amplitude patterns
        if (isSpeaking && amplitude > 0.02f) {
            targetViseme = when {
                // Sharp attack = plosive (B, P, M)
                amplitudeVelocity > 2f && amplitude > 0.3f -> Viseme.MBP
                // High sustained = open vowel (AA)
                amplitude > 0.5f -> Viseme.AA
                // Medium with variation = EE or OH
                amplitude > 0.3f -> if (sin(visemeTimer * 8f) > 0) Viseme.EE else Viseme.OH
                // Lower amplitude = rounded sounds
                amplitude > 0.15f -> Viseme.OO
                // Quiet fricatives
                amplitude > 0.05f -> if (sin(visemeTimer * 12f) > 0.5f) Viseme.FV else Viseme.TH
                else -> Viseme.NEUTRAL
            }

            // Vary visemes more naturally with pseudo-random timing
            if (visemeTimer > 0.08f + Random.nextFloat() * 0.06f) {
                currentViseme = targetViseme
                visemeTimer = 0f
            }
        } else {
            targetViseme = Viseme.NEUTRAL
            currentViseme = Viseme.NEUTRAL
        }

        // Calculate mouth shape parameters from viseme
        val targetOpen = when (currentViseme) {
            Viseme.AA -> 1.0f
            Viseme.OH -> 0.7f
            Viseme.EE -> 0.3f
            Viseme.OO -> 0.4f
            Viseme.FV -> 0.15f
            Viseme.TH -> 0.2f
            Viseme.L -> 0.25f
            Viseme.MBP -> 0.0f
            Viseme.NEUTRAL -> 0.0f
        }

        val targetWide = when (currentViseme) {
            Viseme.EE -> 1.0f
            Viseme.AA -> 0.3f
            else -> 0.0f
        }

        val targetRound = when (currentViseme) {
            Viseme.OO -> 1.0f
            Viseme.OH -> 0.6f
            else -> 0.0f
        }

        val targetTuck = when (currentViseme) {
            Viseme.FV -> 1.0f
            else -> 0.0f
        }

        // Smooth interpolation
        val blendSpeed = 20f
        mouthOpenAmount += (targetOpen - mouthOpenAmount) * deltaTime * blendSpeed
        mouthWideAmount += (targetWide - mouthWideAmount) * deltaTime * blendSpeed
        mouthRoundAmount += (targetRound - mouthRoundAmount) * deltaTime * blendSpeed
        lipTuckAmount += (targetTuck - lipTuckAmount) * deltaTime * blendSpeed
    }

    // ========== Physics Simulation ==========

    private fun updatePhysics(deltaTime: Float) {
        // Fixed timestep accumulator for stable physics
        var accumulator = deltaTime
        while (accumulator >= FIXED_TIMESTEP) {
            integrateVerlet(FIXED_TIMESTEP)
            accumulator -= FIXED_TIMESTEP
        }
    }

    private fun integrateVerlet(dt: Float) {
        val dt2 = dt * dt

        for (i in 0 until pointCount) {
            val idx = i * 3

            // Current position
            var x = positions[idx]
            var y = positions[idx + 1]
            var z = positions[idx + 2]

            // Previous position
            val px = prevPositions[idx]
            val py = prevPositions[idx + 1]
            val pz = prevPositions[idx + 2]

            // Base (rest) position
            val bx = basePositions[idx]
            val by = basePositions[idx + 1]
            val bz = basePositions[idx + 2]

            // === Calculate Forces ===
            var fx = 0f
            var fy = 0f
            var fz = 0f

            // 1. Curl noise turbulence (3D flow field)
            val turbulence = curlNoise(
                x * noiseScale + noiseOffsetX + timeElapsed * 0.3f,
                y * noiseScale + noiseOffsetY,
                z * noiseScale + noiseOffsetZ + timeElapsed * 0.2f
            )
            val turbMult = turbulenceStrength * (1f - faceImpressionStrength * 0.7f)
            fx += turbulence[0] * turbMult
            fy += turbulence[1] * turbMult
            fz += turbulence[2] * turbMult

            // 2. Spring force back to sphere surface
            val currentLen = sqrt(x * x + y * y + z * z)
            val targetRadius = sphereRadius + calculateFaceDisplacement(bx, by, bz) * faceImpressionStrength * 0.35f
            val springForce = (targetRadius - currentLen) * springStiffness
            if (currentLen > 0.001f) {
                fx += (x / currentLen) * springForce
                fy += (y / currentLen) * springForce
                fz += (z / currentLen) * springForce
            }

            // 3. Tangential flow (latitude-based rotation)
            val latitudeFlow = (1f - faceImpressionStrength * 0.5f) * 0.5f
            val tangentX = -z * latitudeFlow
            val tangentZ = x * latitudeFlow
            fx += tangentX
            fz += tangentZ

            // === Verlet Integration ===
            val newX = x + (x - px) * damping + fx * dt2
            val newY = y + (y - py) * damping + fy * dt2
            val newZ = z + (z - pz) * damping + fz * dt2

            // Store previous
            prevPositions[idx] = x
            prevPositions[idx + 1] = y
            prevPositions[idx + 2] = z

            // Update current
            positions[idx] = newX
            positions[idx + 1] = newY
            positions[idx + 2] = newZ
        }
    }

    /**
     * 3D Curl noise for divergence-free turbulence.
     * Creates swirling, smoke-like motion.
     */
    private fun curlNoise(x: Float, y: Float, z: Float): FloatArray {
        val eps = 0.0001f

        // Potential field derivatives (using simplex-like noise approximation)
        val n1 = noise3D(x, y + eps, z) - noise3D(x, y - eps, z)
        val n2 = noise3D(x, y, z + eps) - noise3D(x, y, z - eps)
        val n3 = noise3D(x + eps, y, z) - noise3D(x - eps, y, z)
        val n4 = noise3D(x, y + eps, z) - noise3D(x, y - eps, z)
        val n5 = noise3D(x, y, z + eps) - noise3D(x, y, z - eps)
        val n6 = noise3D(x + eps, y, z) - noise3D(x - eps, y, z)

        // Curl = nabla x F
        val curlX = (n2 - n4) / (2f * eps)
        val curlY = (n3 - n5) / (2f * eps)
        val curlZ = (n1 - n6) / (2f * eps)

        return floatArrayOf(curlX, curlY, curlZ)
    }

    /**
     * Simple 3D noise function (value noise with smooth interpolation)
     */
    private fun noise3D(x: Float, y: Float, z: Float): Float {
        val xi = x.toInt().let { if (x < 0) it - 1 else it }
        val yi = y.toInt().let { if (y < 0) it - 1 else it }
        val zi = z.toInt().let { if (z < 0) it - 1 else it }

        val xf = x - xi
        val yf = y - yi
        val zf = z - zi

        val u = smootherstep(xf)
        val v = smootherstep(yf)
        val w = smootherstep(zf)

        // Hash and interpolate
        val n000 = hash3D(xi, yi, zi)
        val n001 = hash3D(xi, yi, zi + 1)
        val n010 = hash3D(xi, yi + 1, zi)
        val n011 = hash3D(xi, yi + 1, zi + 1)
        val n100 = hash3D(xi + 1, yi, zi)
        val n101 = hash3D(xi + 1, yi, zi + 1)
        val n110 = hash3D(xi + 1, yi + 1, zi)
        val n111 = hash3D(xi + 1, yi + 1, zi + 1)

        val nx00 = lerp(n000, n100, u)
        val nx01 = lerp(n001, n101, u)
        val nx10 = lerp(n010, n110, u)
        val nx11 = lerp(n011, n111, u)

        val nxy0 = lerp(nx00, nx10, v)
        val nxy1 = lerp(nx01, nx11, v)

        return lerp(nxy0, nxy1, w)
    }

    private fun hash3D(x: Int, y: Int, z: Int): Float {
        var h = x * 374761393 + y * 668265263 + z * 1274126177
        h = (h xor (h shr 13)) * 1274126177
        return (h and 0x7fffffff) / 2147483647f
    }

    private fun smootherstep(t: Float): Float = t * t * t * (t * (t * 6 - 15) + 10)
    private fun lerp(a: Float, b: Float, t: Float): Float = a + (b - a) * t

    // ========== Face Displacement - Angelina Jolie Proportions ==========
    // Based on Golden Ratio (1:1.618) facial analysis
    // Key features: high cheekbones, full lips, almond eyes, sharp jaw

    private fun calculateFaceDisplacement(x: Float, y: Float, z: Float): Float {
        if (z < 0.1f) return 0f  // Only front hemisphere

        // Project to face plane with slight perspective
        val faceX = x / (z + 0.3f)
        val faceY = y / (z + 0.3f)

        // Golden ratio face bounds (1:1.618 height to width)
        val faceWidth = 0.55f
        val faceHeight = faceWidth * 1.618f  // ~0.89

        if (faceX.absoluteValue > faceWidth || faceY.absoluteValue > faceHeight / 2) return 0f

        var displacement = 0f
        val zFactor = z.coerceIn(0.3f, 1f)  // Depth scaling

        // === FACE OVAL - Angelina's angular oval ===
        val faceOvalX = faceX / faceWidth
        val faceOvalY = faceY / (faceHeight / 2)
        val inFace = faceOvalX.pow(2) + faceOvalY.pow(2) < 1f
        if (inFace) {
            // Subtle base protrusion, stronger in center
            val centerFalloff = 1f - sqrt(faceOvalX.pow(2) + faceOvalY.pow(2))
            displacement = 0.15f * centerFalloff * zFactor
        }

        // === FOREHEAD - Smooth dome ===
        if (faceY > 0.25f && faceX.absoluteValue < 0.4f) {
            val foreheadFactor = ((faceY - 0.25f) / 0.35f).coerceIn(0f, 1f)
            val foreheadCurve = cos(faceX / 0.4f * PI.toFloat() / 2).pow(2)
            displacement = max(displacement, 0.25f * foreheadFactor * foreheadCurve * zFactor)
        }

        // === BROW RIDGE - Strong, defined (Angelina signature) ===
        val browY = faceY - 0.22f
        if (browY.absoluteValue < 0.08f && faceX.absoluteValue < 0.42f) {
            val browCurve = cos(faceX / 0.42f * PI.toFloat() / 2).pow(1.5f)
            val browPeak = 1f - (browY.absoluteValue / 0.08f)
            displacement = max(displacement, 0.4f * browCurve * browPeak * zFactor)
        }

        // === CHEEKBONES - High and prominent (Angelina's defining feature) ===
        val cheekCenterX = 0.38f
        val cheekCenterY = 0.0f
        val leftCheekDist = sqrt((faceX + cheekCenterX).pow(2) + (faceY - cheekCenterY).pow(2))
        val rightCheekDist = sqrt((faceX - cheekCenterX).pow(2) + (faceY - cheekCenterY).pow(2))
        val cheekDist = min(leftCheekDist, rightCheekDist)
        if (cheekDist < 0.18f) {
            val cheekFactor = (1f - cheekDist / 0.18f).pow(1.5f)
            displacement = max(displacement, 0.55f * cheekFactor * zFactor)  // Strong cheekbones
        }

        // === NOSE - Refined, straight bridge ===
        val noseWidth = 0.06f
        val noseBridgeTop = 0.15f
        val noseTip = -0.18f
        if (faceX.absoluteValue < noseWidth && faceY < noseBridgeTop && faceY > noseTip) {
            val noseLength = noseBridgeTop - noseTip
            val noseProgress = (noseBridgeTop - faceY) / noseLength
            // Nose gets slightly wider and more prominent toward tip
            val noseProfile = 0.5f + 0.5f * sin(noseProgress * PI.toFloat() / 2)
            val noseCenterFalloff = 1f - (faceX.absoluteValue / noseWidth)
            displacement = max(displacement, 0.7f * noseProfile * noseCenterFalloff * zFactor)
        }
        // Nose tip ball
        val noseTipDist = sqrt(faceX.pow(2) + (faceY - noseTip).pow(2))
        if (noseTipDist < 0.07f) {
            displacement = max(displacement, 0.75f * (1f - noseTipDist / 0.07f) * zFactor)
        }

        // === EYES - Wide-set, almond/feline shape (indent) ===
        val eyeY = 0.12f
        val eyeSpacing = 0.22f  // Wide-set
        val eyeWidth = 0.1f
        val eyeHeight = 0.045f  // Almond shape (wider than tall)

        for (eyeX in listOf(-eyeSpacing, eyeSpacing)) {
            val relX = (faceX - eyeX) / eyeWidth
            val relY = (faceY - eyeY) / eyeHeight
            val eyeEllipse = relX.pow(2) + relY.pow(2)
            if (eyeEllipse < 1f) {
                val eyeDepth = (1f - eyeEllipse).pow(0.7f)
                displacement -= 0.25f * eyeDepth * zFactor  // Indent for eye sockets
            }
        }

        // === LIPS - Full, pillowy (Angelina's most famous feature) ===
        val lipCenterY = -0.35f
        val lipWidth = 0.22f
        val upperLipHeight = 0.035f
        val lowerLipHeight = 0.055f  // Fuller lower lip

        val lipY = faceY - lipCenterY
        val lipXNorm = faceX.absoluteValue / lipWidth

        if (lipXNorm < 1f) {
            // Viseme adjustments
            val openAmount = mouthOpenAmount * 0.15f
            val wideStretch = 1f + mouthWideAmount * 0.3f
            val roundCompress = 1f - mouthRoundAmount * 0.25f

            val effectiveLipWidth = lipWidth * wideStretch * roundCompress
            val effectiveLipXNorm = faceX.absoluteValue / effectiveLipWidth

            if (effectiveLipXNorm < 1f) {
                // Upper lip with cupid's bow
                val upperLipY = lipY + openAmount
                if (upperLipY > 0 && upperLipY < upperLipHeight * (1.5f + openAmount * 3f)) {
                    val cupidsBow = if (effectiveLipXNorm < 0.3f) {
                        0.7f + 0.3f * cos(effectiveLipXNorm / 0.3f * PI.toFloat())
                    } else {
                        0.7f * (1f - (effectiveLipXNorm - 0.3f) / 0.7f)
                    }
                    val upperProfile = cupidsBow * (1f - effectiveLipXNorm.pow(2))
                    displacement = max(displacement, 0.5f * upperProfile * zFactor)
                }

                // Lower lip - fuller, pillowy
                val lowerLipY = lipY - openAmount * 1.3f
                if (lowerLipY < 0 && lowerLipY > -lowerLipHeight * (2f + openAmount * 4f)) {
                    val lowerProfile = cos(effectiveLipXNorm * PI.toFloat() / 2).pow(1.3f)
                    val lowerFullness = 1f - (lowerLipY / (-lowerLipHeight * 2f)).pow(2)
                    var lowerDisp = 0.6f * lowerProfile * lowerFullness.coerceIn(0f, 1f) * zFactor

                    // Lip tuck for F/V sounds
                    if (lipTuckAmount > 0.1f) {
                        lowerDisp *= (1f - lipTuckAmount * 0.6f)
                    }
                    displacement = max(displacement, lowerDisp)
                }
            }
        }

        // === JAWLINE - Sharp, angular (Angelina signature) ===
        val jawY = -0.42f
        val jawWidth = 0.45f
        if (faceY < jawY && faceY > -0.55f) {
            val jawProgress = (jawY - faceY) / 0.13f
            val jawAngle = faceX.absoluteValue / (jawWidth * (1f - jawProgress * 0.4f))
            if (jawAngle < 1f) {
                val jawSharpness = (1f - jawAngle).pow(2f) * (1f - jawProgress)
                displacement = max(displacement, 0.35f * jawSharpness * zFactor)
            }
        }

        // === CHIN - Defined, slightly pointed ===
        val chinY = -0.52f
        val chinDist = sqrt(faceX.pow(2) + (faceY - chinY).pow(2))
        if (chinDist < 0.1f) {
            val chinFactor = (1f - chinDist / 0.1f).pow(1.5f)
            displacement = max(displacement, 0.4f * chinFactor * zFactor)
        }

        return displacement.coerceIn(-0.3f, 1f)
    }

    // ========== Rendering ==========

    private fun updateBuffers() {
        vertexBuffer?.clear()
        colorBuffer?.clear()
        sizeBuffer?.clear()

        for (i in 0 until pointCount) {
            val idx = i * 3
            val x = positions[idx]
            val y = positions[idx + 1]
            val z = positions[idx + 2]

            vertexBuffer?.put(x)
            vertexBuffer?.put(y)
            vertexBuffer?.put(z)

            val displacement = calculateFaceDisplacement(
                basePositions[idx], basePositions[idx + 1], basePositions[idx + 2]
            )

            val color = calculatePointColor(x, y, z, displacement)
            colorBuffer?.put(color[0])
            colorBuffer?.put(color[1])
            colorBuffer?.put(color[2])
            colorBuffer?.put(color[3])

            sizeBuffer?.put(calculatePointSize(displacement))
        }

        vertexBuffer?.position(0)
        colorBuffer?.position(0)
        sizeBuffer?.position(0)
    }

    private fun calculatePointColor(x: Float, y: Float, z: Float, displacement: Float): FloatArray {
        val hue = (timeElapsed * 0.08f + y * 0.3f) % 1f

        var r = 0.05f + hue * 0.15f
        var g = 0.65f + displacement * 0.35f
        var b = 0.95f
        var a = 0.5f + displacement * 0.5f + faceImpressionStrength * 0.2f

        // Lip area glows during speech
        if (displacement > 0.3f && faceImpressionStrength > 0.5f) {
            val speechGlow = mouthOpenAmount * 0.3f
            r += 0.3f * displacement + speechGlow
            g = min(1f, g + 0.15f)
        }

        // Eyes glow
        if (displacement < 0) {
            r = 0.1f
            g = 1f
            b = 1f
            a = 0.9f
        }

        // Shimmer
        val shimmer = sin(timeElapsed * 4f + x * 8f + y * 8f) * 0.08f
        g += shimmer

        return floatArrayOf(
            r.coerceIn(0f, 1f), g.coerceIn(0f, 1f),
            b.coerceIn(0f, 1f), a.coerceIn(0f, 1f)
        )
    }

    private fun calculatePointSize(displacement: Float): Float {
        var size = 3.5f + displacement * 5f
        size *= 1f + sin(timeElapsed * 2.5f) * 0.08f
        size *= 0.6f + faceImpressionStrength * 0.4f
        // Larger for mouth when speaking
        if (displacement > 0.3f && mouthOpenAmount > 0.2f) {
            size *= 1f + mouthOpenAmount * 0.3f
        }
        return size.coerceIn(2f, 14f)
    }

    private fun renderPoints() {
        GLES20.glUseProgram(shaderProgram)

        val posHandle = GLES20.glGetAttribLocation(shaderProgram, "aPosition")
        val colorHandle = GLES20.glGetAttribLocation(shaderProgram, "aColor")
        val sizeHandle = GLES20.glGetAttribLocation(shaderProgram, "aPointSize")
        val mvpHandle = GLES20.glGetUniformLocation(shaderProgram, "uMVPMatrix")

        GLES20.glUniformMatrix4fv(mvpHandle, 1, false, mvpMatrix, 0)

        GLES20.glEnableVertexAttribArray(posHandle)
        GLES20.glEnableVertexAttribArray(colorHandle)
        GLES20.glEnableVertexAttribArray(sizeHandle)

        GLES20.glVertexAttribPointer(posHandle, 3, GLES20.GL_FLOAT, false, 12, vertexBuffer)
        GLES20.glVertexAttribPointer(colorHandle, 4, GLES20.GL_FLOAT, false, 16, colorBuffer)
        GLES20.glVertexAttribPointer(sizeHandle, 1, GLES20.GL_FLOAT, false, 4, sizeBuffer)

        GLES20.glDrawArrays(GLES20.GL_POINTS, 0, pointCount)

        GLES20.glDisableVertexAttribArray(posHandle)
        GLES20.glDisableVertexAttribArray(colorHandle)
        GLES20.glDisableVertexAttribArray(sizeHandle)
    }

    private fun createShaderProgram(): Int {
        val vs = GLES20.glCreateShader(GLES20.GL_VERTEX_SHADER).also {
            GLES20.glShaderSource(it, VERTEX_SHADER)
            GLES20.glCompileShader(it)
        }
        val fs = GLES20.glCreateShader(GLES20.GL_FRAGMENT_SHADER).also {
            GLES20.glShaderSource(it, FRAGMENT_SHADER)
            GLES20.glCompileShader(it)
        }
        return GLES20.glCreateProgram().also {
            GLES20.glAttachShader(it, vs)
            GLES20.glAttachShader(it, fs)
            GLES20.glLinkProgram(it)
        }
    }

    fun resetAnimation() {
        faceImpressionStrength = 0f
        isSpeaking = false
        silenceTimer = 0f
        mouthOpenAmount = 0f
        currentViseme = Viseme.NEUTRAL
    }

    fun skipToFace() {
        faceImpressionStrength = 1f
        isSpeaking = true
    }
}

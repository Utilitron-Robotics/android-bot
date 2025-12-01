package com.opendroids.tourbot.ui.components.pointcloud

import android.opengl.GLES20
import android.opengl.GLSurfaceView
import android.opengl.Matrix
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10
import kotlin.math.PI
import kotlin.math.acos
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.random.Random

class PointCloudRenderer : GLSurfaceView.Renderer {

    @Volatile var amplitude: Float = 0f
    @Volatile var isSpeaking: Boolean = false

    private lateinit var positions: FloatArray
    private lateinit var velocities: FloatArray
    private lateinit var basePositions: FloatArray
    private lateinit var energyLevels: FloatArray
    private var pointCount = 0

    private lateinit var lineIndices: IntArray
    private var lineCount = 0
    private lateinit var neighborMap: Array<IntArray>

    private var vertexBuffer: FloatBuffer? = null
    private var colorBuffer: FloatBuffer? = null
    private var sizeBuffer: FloatBuffer? = null
    private var lineVertexBuffer: FloatBuffer? = null
    private var lineColorBuffer: FloatBuffer? = null

    private var pointShaderProgram = 0
    private var lineShaderProgram = 0

    private val mvpMatrix = FloatArray(16)
    private val projectionMatrix = FloatArray(16)
    private val viewMatrix = FloatArray(16)
    private val modelMatrix = FloatArray(16)

    private var timeElapsed = 0f
    private var lastFrameTime = System.nanoTime()
    private var globalRotation = 0f
    private var lastPulseTime = 0f

    companion object {
        private const val POINT_COUNT = 2500
        private const val NEIGHBOR_DISTANCE_THRESHOLD = 0.22f
        private const val MAX_NEIGHBORS = 3
        private const val FIXED_TIMESTEP = 1f / 60f
    }

    private val POINT_VERTEX_SHADER = """
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
    private val POINT_FRAGMENT_SHADER = """
        precision mediump float;
        varying vec4 vColor;
        void main() {
            vec2 coord = gl_PointCoord - vec2(0.5);
            float dist = length(coord);
            float alpha = 1.0 - smoothstep(0.4, 0.5, dist);
            gl_FragColor = vec4(vColor.rgb, vColor.a * alpha);
        }
    """
    private val LINE_VERTEX_SHADER = """
        uniform mat4 uMVPMatrix;
        attribute vec4 aPosition;
        attribute vec4 aColor;
        varying vec4 vColor;
        void main() {
            gl_Position = uMVPMatrix * aPosition;
            vColor = aColor;
        }
    """
    private val LINE_FRAGMENT_SHADER = """
        precision mediump float;
        varying vec4 vColor;
        void main() {
            gl_FragColor = vColor;
        }
    """

    override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
        GLES20.glClearColor(0.0f, 0.0f, 0.0f, 0.0f)
        GLES20.glEnable(GLES20.GL_BLEND)
        GLES20.glBlendFunc(GLES20.GL_SRC_ALPHA, GLES20.GL_ONE)
        initializePoints()
        pointShaderProgram = createShaderProgram(POINT_VERTEX_SHADER, POINT_FRAGMENT_SHADER)
        lineShaderProgram = createShaderProgram(LINE_VERTEX_SHADER, LINE_FRAGMENT_SHADER)
    }

    private fun initializePoints() {
        pointCount = POINT_COUNT
        positions = FloatArray(pointCount * 3)
        basePositions = FloatArray(pointCount * 3)
        velocities = FloatArray(pointCount * 3)
        energyLevels = FloatArray(pointCount)

        generateBrainShape()

        System.arraycopy(basePositions, 0, positions, 0, basePositions.size)
        buildNeighborMap()

        vertexBuffer = createFloatBuffer(pointCount * 3)
        colorBuffer = createFloatBuffer(pointCount * 4)
        sizeBuffer = createFloatBuffer(pointCount)
        lineVertexBuffer = createFloatBuffer(lineCount * 3)
        lineColorBuffer = createFloatBuffer(lineCount * 4)
    }

    private fun generateBrainShape() {
        val goldenRatio = (1.0 + sqrt(5.0)) / 2.0
        for (i in 0 until POINT_COUNT) {
            val theta = (2.0 * PI * i / goldenRatio).toFloat()
            val phi = acos(1.0 - 2.0 * (i + 0.5) / POINT_COUNT).toFloat()
            
            var x = cos(theta) * sin(phi)
            var y = sin(theta) * sin(phi)
            var z = cos(phi)

            // Deform sphere into a brain-like shape
            x *= 1.0f  // Width (hemispheres)
            y *= 0.8f  // Height (flatten top/bottom)
            z *= 0.9f  // Depth (front to back)

            // Central fissure
            val fissureDepth = 0.15f
            val fissureWidth = 0.1f
            x -= (fissureDepth * exp(-(x * x) / (fissureWidth * fissureWidth))).toFloat()

            // Add gyri/sulci details with noise
            val noiseScale = 6f
            val noiseStrength = 0.04f
            val noiseX = noise(x * noiseScale, y * noiseScale, z * noiseScale, 0f) * noiseStrength
            val noiseY = noise(x * noiseScale, y * noiseScale, z * noiseScale, 1f) * noiseStrength
            val noiseZ = noise(x * noiseScale, y * noiseScale, z * noiseScale, 2f) * noiseStrength
            
            val finalScale = 1.6f
            val offsetY = 0.1f
            val idx = i * 3
            basePositions[idx] = (x + noiseX) * finalScale
            basePositions[idx + 1] = (y + noiseY + offsetY) * finalScale
            basePositions[idx + 2] = (z + noiseZ) * finalScale
        }
    }

    private fun buildNeighborMap() {
        val neighborList = Array(pointCount) { mutableListOf<Int>() }
        val lineIndexList = mutableListOf<Int>()

        for (i in 0 until pointCount) {
            val neighbors = mutableListOf<Pair<Int, Float>>()
            for (j in (i + 1) until pointCount) {
                val dx = basePositions[i * 3] - basePositions[j * 3]
                val dy = basePositions[i * 3 + 1] - basePositions[j * 3 + 1]
                val dz = basePositions[i * 3 + 2] - basePositions[j * 3 + 2]
                val distSq = dx * dx + dy * dy + dz * dz
                if (distSq < NEIGHBOR_DISTANCE_THRESHOLD * NEIGHBOR_DISTANCE_THRESHOLD) {
                    neighbors.add(j to distSq)
                }
            }
            neighbors.sortBy { it.second }
            for (k in 0 until minOf(MAX_NEIGHBORS, neighbors.size)) {
                val neighborIndex = neighbors[k].first
                neighborList[i].add(neighborIndex)
                neighborList[neighborIndex].add(i)
                lineIndexList.add(i)
                lineIndexList.add(neighborIndex)
            }
        }
        neighborMap = Array(pointCount) { i -> neighborList[i].distinct().toIntArray() }
        lineIndices = lineIndexList.distinct().toIntArray()
        lineCount = lineIndices.size
    }

    override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
        GLES20.glViewport(0, 0, width, height)
        val ratio = width.toFloat() / height.toFloat()
        Matrix.frustumM(projectionMatrix, 0, -ratio, ratio, -1f, 1f, 1f, 20f)
        Matrix.setLookAtM(viewMatrix, 0, 0f, 0f, 3.5f, 0f, 0f, 0f, 0f, 1f, 0f)
    }

    override fun onDrawFrame(gl: GL10?) {
        val deltaTime = ((System.nanoTime() - lastFrameTime) / 1_000_000_000f).coerceAtMost(0.1f)
        lastFrameTime = System.nanoTime()
        timeElapsed += deltaTime

        updatePhysicsAndEnergy()

        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)

        Matrix.setIdentityM(modelMatrix, 0)
        if (!isSpeaking) {
            globalRotation += deltaTime * 12f
        }
        Matrix.rotateM(modelMatrix, 0, globalRotation, 0.2f, 1f, 0.3f)
        Matrix.multiplyMM(mvpMatrix, 0, viewMatrix, 0, modelMatrix, 0)
        Matrix.multiplyMM(mvpMatrix, 0, projectionMatrix, 0, mvpMatrix, 0)

        drawLines()
        drawPoints()
    }

    private fun updatePhysicsAndEnergy() {
        if (isSpeaking && (timeElapsed - lastPulseTime > 0.05f)) {
            val pulseCount = (amplitude * 40).toInt() + 3
            for (i in 0 until pulseCount) {
                val pointIndex = Random.nextInt(pointCount)
                energyLevels[pointIndex] = max(energyLevels[pointIndex], Random.nextFloat() * 0.7f + 0.3f)
            }
            lastPulseTime = timeElapsed
        }

        val nextEnergyLevels = FloatArray(pointCount)
        val energyPropagationFactor = 0.4f
        val energyDecayFactor = 1.0f - 2.8f * FIXED_TIMESTEP

        for (i in 0 until pointCount) {
            var propagatedEnergy = 0f
            if (neighborMap[i].isNotEmpty()) {
                for (neighborIndex in neighborMap[i]) {
                    propagatedEnergy += energyLevels[neighborIndex]
                }
                nextEnergyLevels[i] = max(
                    energyLevels[i] * energyDecayFactor,
                    propagatedEnergy * energyPropagationFactor / neighborMap[i].size.toFloat()
                )
            } else {
                nextEnergyLevels[i] = energyLevels[i] * energyDecayFactor
            }
        }
        System.arraycopy(nextEnergyLevels, 0, energyLevels, 0, pointCount)

        val breathing = sin(timeElapsed * 1.8f) * 0.015f
        for (i in 0 until pointCount) {
            val idx = i * 3
            val targetX = basePositions[idx] * (1.0f + breathing)
            val targetY = basePositions[idx + 1] * (1.0f + breathing)
            val targetZ = basePositions[idx + 2] * (1.0f + breathing)

            val fx = (targetX - positions[idx]) * 18.0f
            val fy = (targetY - positions[idx + 1]) * 18.0f
            val fz = (targetZ - positions[idx + 2]) * 18.0f

            velocities[idx] += fx * FIXED_TIMESTEP
            velocities[idx + 1] += fy * FIXED_TIMESTEP
            velocities[idx + 2] += fz * FIXED_TIMESTEP

            val noise = curlNoise(positions[idx] * 0.6f, positions[idx + 1] * 0.6f, positions[idx + 2] * 0.6f, timeElapsed)
            velocities[idx] += noise[0] * 0.6f
            velocities[idx + 1] += noise[1] * 0.6f
            velocities[idx + 2] += noise[2] * 0.6f

            velocities[idx] *= 0.85f
            velocities[idx + 1] *= 0.85f
            velocities[idx + 2] *= 0.85f

            positions[idx] += velocities[idx] * FIXED_TIMESTEP
            positions[idx + 1] += velocities[idx + 1] * FIXED_TIMESTEP
            positions[idx + 2] += velocities[idx + 2] * FIXED_TIMESTEP
        }
    }

    private fun drawPoints() {
        GLES20.glUseProgram(pointShaderProgram)
        vertexBuffer?.clear(); colorBuffer?.clear(); sizeBuffer?.clear()
        for (i in 0 until pointCount) {
            val idx = i * 3
            vertexBuffer?.put(positions, idx, 3)
            val energy = energyLevels[i]
            val r = lerp(0.2f, 0.9f, energy)
            val g = lerp(0.5f, 1.0f, energy)
            val b = 1.0f
            val a = (0.5f + energy * 0.5f).coerceIn(0.2f, 1f)
            colorBuffer?.put(r)?.put(g)?.put(b)?.put(a)
            sizeBuffer?.put((1.0f + energy * 5.5f).coerceIn(0.5f, 6.5f))
        }
        setupAndDraw(pointShaderProgram, GLES20.GL_POINTS, pointCount, vertexBuffer, colorBuffer, sizeBuffer)
    }

    private fun drawLines() {
        GLES20.glUseProgram(lineShaderProgram)
        lineVertexBuffer?.clear(); lineColorBuffer?.clear()
        for (i in 0 until lineCount step 2) {
            val p1Index = lineIndices[i]
            val p2Index = lineIndices[i + 1]
            val energy = max(energyLevels[p1Index], energyLevels[p2Index])
            val alpha = (energy * 0.35f).coerceIn(0.0f, 0.2f)
            
            lineVertexBuffer?.put(positions, p1Index * 3, 3)
            lineColorBuffer?.put(0.4f)?.put(0.8f)?.put(1.0f)?.put(alpha)
            lineVertexBuffer?.put(positions, p2Index * 3, 3)
            lineColorBuffer?.put(0.4f)?.put(0.8f)?.put(1.0f)?.put(alpha)
        }
        GLES20.glLineWidth(1.2f)
        setupAndDraw(lineShaderProgram, GLES20.GL_LINES, lineCount, lineVertexBuffer, lineColorBuffer)
    }

    private fun setupAndDraw(program: Int, mode: Int, count: Int, vtxBuf: FloatBuffer?, colBuf: FloatBuffer?, sizeBuf: FloatBuffer? = null) {
        vtxBuf?.position(0); colBuf?.position(0); sizeBuf?.position(0)
        val pos = GLES20.glGetAttribLocation(program, "aPosition")
        val col = GLES20.glGetAttribLocation(program, "aColor")
        GLES20.glEnableVertexAttribArray(pos); GLES20.glEnableVertexAttribArray(col)
        GLES20.glVertexAttribPointer(pos, 3, GLES20.GL_FLOAT, false, 12, vtxBuf)
        GLES20.glVertexAttribPointer(col, 4, GLES20.GL_FLOAT, false, 16, colBuf)
        
        val size = GLES20.glGetAttribLocation(program, "aPointSize")
        if (size != -1 && sizeBuf != null) {
            GLES20.glEnableVertexAttribArray(size)
            GLES20.glVertexAttribPointer(size, 1, GLES20.GL_FLOAT, false, 4, sizeBuf)
        }

        GLES20.glUniformMatrix4fv(GLES20.glGetUniformLocation(program, "uMVPMatrix"), 1, false, mvpMatrix, 0)
        GLES20.glDrawArrays(mode, 0, count)

        GLES20.glDisableVertexAttribArray(pos); GLES20.glDisableVertexAttribArray(col)
        if (size != -1) GLES20.glDisableVertexAttribArray(size)
    }

    private fun createShaderProgram(vtx: String, frag: String): Int {
        val vs = GLES20.glCreateShader(GLES20.GL_VERTEX_SHADER).also { GLES20.glShaderSource(it, vtx); GLES20.glCompileShader(it) }
        val fs = GLES20.glCreateShader(GLES20.GL_FRAGMENT_SHADER).also { GLES20.glShaderSource(it, frag); GLES20.glCompileShader(it) }
        return GLES20.glCreateProgram().also { GLES20.glAttachShader(it, vs); GLES20.glAttachShader(it, fs); GLES20.glLinkProgram(it) }
    }
    
    private fun curlNoise(x: Float, y: Float, z: Float, t: Float): FloatArray {
        val eps = 0.01f
        val n1x = noise(x, y + eps, z, t); val n1y = noise(x, y - eps, z, t)
        val n2x = noise(x, y, z + eps, t); val n2y = noise(x, y, z - eps, t)
        val n3x = noise(x + eps, y, z, t); val n3y = noise(x - eps, y, z, t)
        
        val dx = (n2x - n2y) - (n1x - n1y)
        val dy = (n3x - n3y) - (n2x - n2y)
        val dz = (n1x - n1y) - (n3x - n3y)
        
        return floatArrayOf(dx, dy, dz)
    }

    private fun noise(x: Float, y: Float, z: Float, w: Float): Float {
        val i = floor(x); val j = floor(y); val k = floor(z); val l = floor(w)
        val f = x - i; val g = y - j; val h = z - k; val m = w - l
        val u = f*f*f*(f*(f*6-15)+10); val v = g*g*g*(g*(g*6-15)+10)
        val r = h*h*h*(h*(h*6-15)+10)
        return lerp(
            lerp(
                lerp(grad(hash(i,j,k,l),f,g,h,m), grad(hash(i+1,j,k,l),f-1,g,h,m), u),
                lerp(grad(hash(i,j+1,k,l),f,g-1,h,m), grad(hash(i+1,j+1,k,l),f-1,g-1,h,m), u), v),
            lerp(
                lerp(grad(hash(i,j,k+1,l),f,g,h-1,m), grad(hash(i+1,j,k+1,l),f-1,g,h-1,m), u),
                lerp(grad(hash(i,j+1,k+1,l),f,g-1,h-1,m), grad(hash(i+1,j+1,k+1,l),f-1,g-1,h-1,m), u), v), r)
    }
    private fun lerp(a: Float, b: Float, t: Float) = a + t * (b - a)
    private fun grad(hash: Int, x: Float, y: Float, z: Float, w: Float) = (if((hash and 8)!=0) x else -x) + (if((hash and 4)!=0) y else -y) + (if((hash and 2)!=0) z else -z) + (if((hash and 1)!=0) w else -w)
    private fun hash(x: Float, y: Float, z: Float, w: Float): Int {
        val p1 = 73856093 * x; val p2 = 19349663 * y; val p3 = 83492791 * z; val p4 = 47188699 * w
        return (p1 + p2 + p3 + p4).toInt()
    }

    private fun createFloatBuffer(capacity: Int): FloatBuffer {
        return ByteBuffer.allocateDirect(capacity * 4).order(ByteOrder.nativeOrder()).asFloatBuffer()
    }

    fun skipToFace() { /* No longer used */ }
}

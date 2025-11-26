package com.opendroids.tourbot.ui.components.pointcloud

import kotlin.math.*
import kotlin.random.Random

/**
 * Generates point cloud geometry for a female face.
 * Points are distributed to form facial features that can be animated.
 */
object FaceGeometry {

    data class FacePoint(
        val x: Float,
        val y: Float,
        val z: Float,
        val region: FaceRegion,
        val intensity: Float = 1f
    )

    enum class FaceRegion {
        FACE_OUTLINE,
        LEFT_EYE,
        RIGHT_EYE,
        LEFT_EYEBROW,
        RIGHT_EYEBROW,
        NOSE,
        UPPER_LIP,
        LOWER_LIP,
        CHEEK_LEFT,
        CHEEK_RIGHT,
        FOREHEAD,
        CHIN,
        JAW
    }

    /**
     * Generate a complete female face point cloud.
     * Coordinates are normalized to [-1, 1] range.
     */
    fun generateFacePoints(totalPoints: Int = 3000): List<FacePoint> {
        val points = mutableListOf<FacePoint>()

        // Distribution of points across regions
        val faceOutlinePoints = (totalPoints * 0.15).toInt()
        val eyePoints = (totalPoints * 0.08).toInt()
        val eyebrowPoints = (totalPoints * 0.04).toInt()
        val nosePoints = (totalPoints * 0.06).toInt()
        val lipPoints = (totalPoints * 0.10).toInt()
        val cheekPoints = (totalPoints * 0.08).toInt()
        val foreheadPoints = (totalPoints * 0.10).toInt()
        val chinJawPoints = (totalPoints * 0.08).toInt()
        val fillPoints = totalPoints - (faceOutlinePoints + eyePoints * 2 + eyebrowPoints * 2 +
                         nosePoints + lipPoints * 2 + cheekPoints * 2 + foreheadPoints + chinJawPoints)

        // Face outline - elegant oval with feminine proportions
        points.addAll(generateFaceOutline(faceOutlinePoints))

        // Eyes - almond shaped, slightly larger for feminine look
        points.addAll(generateEye(eyePoints, isLeft = true))
        points.addAll(generateEye(eyePoints, isLeft = false))

        // Eyebrows - arched, feminine shape
        points.addAll(generateEyebrow(eyebrowPoints, isLeft = true))
        points.addAll(generateEyebrow(eyebrowPoints, isLeft = false))

        // Nose - delicate, smaller
        points.addAll(generateNose(nosePoints))

        // Lips - fuller, defined
        points.addAll(generateLips(lipPoints, isUpper = true))
        points.addAll(generateLips(lipPoints, isUpper = false))

        // Cheeks - soft contours
        points.addAll(generateCheek(cheekPoints, isLeft = true))
        points.addAll(generateCheek(cheekPoints, isLeft = false))

        // Forehead
        points.addAll(generateForehead(foreheadPoints))

        // Chin and jaw
        points.addAll(generateChinJaw(chinJawPoints))

        // Fill points for face surface
        points.addAll(generateFaceFill(fillPoints))

        return points
    }

    private fun generateFaceOutline(count: Int): List<FacePoint> {
        val points = mutableListOf<FacePoint>()
        for (i in 0 until count) {
            val t = i.toFloat() / count * 2 * PI.toFloat()
            // Feminine oval - narrower at jaw, wider at cheekbones
            val radiusX = 0.65f + 0.1f * sin(t) * sin(t)
            val radiusY = 0.85f
            val x = radiusX * sin(t)
            val y = radiusY * cos(t)
            val z = 0.1f * cos(t * 2) + randomJitter(0.02f)
            points.add(FacePoint(x, y, z, FaceRegion.FACE_OUTLINE))
        }
        return points
    }

    private fun generateEye(count: Int, isLeft: Boolean): List<FacePoint> {
        val points = mutableListOf<FacePoint>()
        val centerX = if (isLeft) -0.25f else 0.25f
        val centerY = 0.15f
        val region = if (isLeft) FaceRegion.LEFT_EYE else FaceRegion.RIGHT_EYE

        // Almond eye shape
        for (i in 0 until count) {
            val t = i.toFloat() / count * 2 * PI.toFloat()
            // Almond shape: wider horizontally, pointed at corners
            val radiusX = 0.12f * (1 + 0.3f * cos(t))
            val radiusY = 0.06f * sin(PI.toFloat() / 2 + t / 2).absoluteValue
            val x = centerX + radiusX * cos(t)
            val y = centerY + radiusY * sin(t)
            val z = 0.15f + randomJitter(0.01f)
            points.add(FacePoint(x, y, z, region, intensity = 1.2f))
        }

        // Pupil points (denser center)
        for (i in 0 until count / 3) {
            val angle = Random.nextFloat() * 2 * PI.toFloat()
            val r = Random.nextFloat() * 0.04f
            val x = centerX + r * cos(angle)
            val y = centerY + r * sin(angle)
            val z = 0.18f + randomJitter(0.005f)
            points.add(FacePoint(x, y, z, region, intensity = 1.5f))
        }

        return points
    }

    private fun generateEyebrow(count: Int, isLeft: Boolean): List<FacePoint> {
        val points = mutableListOf<FacePoint>()
        val startX = if (isLeft) -0.38f else 0.18f
        val endX = if (isLeft) -0.12f else 0.38f
        val region = if (isLeft) FaceRegion.LEFT_EYEBROW else FaceRegion.RIGHT_EYEBROW

        for (i in 0 until count) {
            val t = i.toFloat() / count
            val x = startX + (endX - startX) * t
            // Arched eyebrow with peak at 1/3 from inner corner
            val archHeight = 0.04f * sin(t * PI.toFloat()) * (1 + 0.5f * (1 - t))
            val y = 0.32f + archHeight
            val z = 0.12f + randomJitter(0.01f)
            points.add(FacePoint(x, y, z, region))
        }
        return points
    }

    private fun generateNose(count: Int): List<FacePoint> {
        val points = mutableListOf<FacePoint>()

        // Nose bridge
        for (i in 0 until count / 2) {
            val t = i.toFloat() / (count / 2)
            val y = 0.1f - t * 0.35f
            val x = randomJitter(0.015f)
            val z = 0.2f + t * 0.15f + randomJitter(0.01f)
            points.add(FacePoint(x, y, z, FaceRegion.NOSE))
        }

        // Nose tip and nostrils (delicate, feminine)
        for (i in 0 until count / 2) {
            val angle = Random.nextFloat() * 2 * PI.toFloat()
            val r = Random.nextFloat() * 0.06f
            val x = r * cos(angle)
            val y = -0.22f + r * sin(angle) * 0.5f
            val z = 0.35f - r * 0.5f + randomJitter(0.01f)
            points.add(FacePoint(x, y, z, FaceRegion.NOSE, intensity = 0.9f))
        }

        return points
    }

    private fun generateLips(count: Int, isUpper: Boolean): List<FacePoint> {
        val points = mutableListOf<FacePoint>()
        val region = if (isUpper) FaceRegion.UPPER_LIP else FaceRegion.LOWER_LIP
        val baseY = if (isUpper) -0.38f else -0.45f

        for (i in 0 until count) {
            val t = (i.toFloat() / count) * 2 - 1  // -1 to 1
            val x = t * 0.22f

            val y = if (isUpper) {
                // Cupid's bow shape for upper lip
                val cupidsBow = 0.025f * cos(t * PI.toFloat() * 2)
                baseY + cupidsBow + 0.02f * (1 - t.absoluteValue)
            } else {
                // Fuller lower lip
                baseY - 0.04f * sqrt(1 - t * t) + randomJitter(0.005f)
            }

            val z = 0.25f + 0.05f * (1 - t.absoluteValue) + randomJitter(0.01f)
            points.add(FacePoint(x, y, z, region, intensity = 1.1f))
        }

        return points
    }

    private fun generateCheek(count: Int, isLeft: Boolean): List<FacePoint> {
        val points = mutableListOf<FacePoint>()
        val centerX = if (isLeft) -0.4f else 0.4f
        val centerY = -0.05f
        val region = if (isLeft) FaceRegion.CHEEK_LEFT else FaceRegion.CHEEK_RIGHT

        for (i in 0 until count) {
            val angle = Random.nextFloat() * 2 * PI.toFloat()
            val r = Random.nextFloat() * 0.15f
            val x = centerX + r * cos(angle)
            val y = centerY + r * sin(angle) * 1.2f
            val z = 0.08f + 0.1f * (1 - r / 0.15f) + randomJitter(0.02f)
            points.add(FacePoint(x, y, z, region, intensity = 0.7f))
        }

        return points
    }

    private fun generateForehead(count: Int): List<FacePoint> {
        val points = mutableListOf<FacePoint>()

        for (i in 0 until count) {
            val x = (Random.nextFloat() * 2 - 1) * 0.5f
            val y = 0.4f + Random.nextFloat() * 0.35f
            val z = 0.05f + 0.08f * (1 - (y - 0.4f) / 0.35f) + randomJitter(0.02f)
            points.add(FacePoint(x, y, z, FaceRegion.FOREHEAD, intensity = 0.6f))
        }

        return points
    }

    private fun generateChinJaw(count: Int): List<FacePoint> {
        val points = mutableListOf<FacePoint>()

        // Chin
        for (i in 0 until count / 2) {
            val angle = Random.nextFloat() * PI.toFloat() - PI.toFloat() / 2
            val r = Random.nextFloat() * 0.12f
            val x = r * cos(angle)
            val y = -0.7f + r * sin(angle).absoluteValue * 0.5f
            val z = 0.1f + randomJitter(0.02f)
            points.add(FacePoint(x, y, z, FaceRegion.CHIN, intensity = 0.8f))
        }

        // Jawline
        for (i in 0 until count / 2) {
            val t = (i.toFloat() / (count / 2)) * 2 - 1
            val x = t * 0.55f
            val y = -0.55f - 0.15f * t.absoluteValue
            val z = 0.02f + 0.05f * (1 - t.absoluteValue) + randomJitter(0.01f)
            points.add(FacePoint(x, y, z, FaceRegion.JAW, intensity = 0.75f))
        }

        return points
    }

    private fun generateFaceFill(count: Int): List<FacePoint> {
        val points = mutableListOf<FacePoint>()

        for (i in 0 until count) {
            // Random point within face bounds
            val x = (Random.nextFloat() * 2 - 1) * 0.55f
            val y = (Random.nextFloat() * 2 - 1) * 0.75f

            // Check if point is within face oval
            val inFace = (x / 0.6f).pow(2) + (y / 0.8f).pow(2) < 1
            if (inFace) {
                // Avoid eye regions
                val inLeftEye = (x + 0.25f).pow(2) / 0.015f + (y - 0.15f).pow(2) / 0.005f < 1
                val inRightEye = (x - 0.25f).pow(2) / 0.015f + (y - 0.15f).pow(2) / 0.005f < 1

                if (!inLeftEye && !inRightEye) {
                    val z = 0.05f + 0.1f * (1 - sqrt(x.pow(2) + y.pow(2))) + randomJitter(0.03f)
                    points.add(FacePoint(x, y, z, FaceRegion.FACE_OUTLINE, intensity = 0.4f))
                }
            }
        }

        return points
    }

    private fun randomJitter(amount: Float): Float = (Random.nextFloat() * 2 - 1) * amount

    /**
     * Generate random sphere points for the swirling globe effect.
     */
    fun generateSpherePoints(count: Int): List<FloatArray> {
        val points = mutableListOf<FloatArray>()
        for (i in 0 until count) {
            // Fibonacci sphere for even distribution
            val phi = acos(1 - 2 * (i + 0.5f) / count)
            val theta = PI.toFloat() * (1 + sqrt(5f)) * i

            val x = sin(phi) * cos(theta)
            val y = sin(phi) * sin(theta)
            val z = cos(phi)

            points.add(floatArrayOf(x, y, z))
        }
        return points
    }
}

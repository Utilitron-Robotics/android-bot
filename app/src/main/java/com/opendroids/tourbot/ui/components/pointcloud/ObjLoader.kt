package com.opendroids.tourbot.ui.components.pointcloud

import android.content.Context
import java.io.BufferedReader
import java.io.InputStreamReader

object ObjLoader {
    fun load(context: Context, assetPath: String): FloatArray {
        val vertices = mutableListOf<Float>()
        try {
            val inputStream = context.assets.open(assetPath)
            val reader = BufferedReader(InputStreamReader(inputStream))
            reader.forEachLine { line ->
                if (line.startsWith("v ")) {
                    val parts = line.split(" ").filter { it.isNotBlank() }
                    if (parts.size >= 4) {
                        vertices.add(parts[1].toFloat())
                        vertices.add(parts[2].toFloat())
                        vertices.add(parts[3].toFloat())
                    }
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return vertices.toFloatArray()
    }
}

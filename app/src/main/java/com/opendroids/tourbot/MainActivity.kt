package com.opendroids.tourbot

import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import com.opendroids.tourbot.robot.Robot
import com.opendroids.tourbot.ui.MainScreen
import com.opendroids.tourbot.ui.audio.AudioPlayer
import dagger.hilt.android.AndroidEntryPoint
import javax.inject.Inject

@AndroidEntryPoint
class MainActivity : ComponentActivity() {

    @Inject
    lateinit var audioPlayer: AudioPlayer

    @Inject
    lateinit var robot: Robot

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        setContent {
            MainScreen(
                audioPlayer = audioPlayer,
                robot = robot
            )
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        audioPlayer.release()
    }
}

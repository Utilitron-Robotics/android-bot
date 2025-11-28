package com.opendroids.tourbot

import android.Manifest
import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Text
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import com.opendroids.tourbot.data.MasterTourRepository
import com.opendroids.tourbot.data.TourConfigRepository
import com.opendroids.tourbot.data.model.TourState
import com.opendroids.tourbot.logic.TourManager
import com.opendroids.tourbot.ui.MainScreen
import com.opendroids.tourbot.ui.MainViewModel
import com.opendroids.tourbot.ui.audio.AudioPlayer
import dagger.hilt.android.AndroidEntryPoint
import javax.inject.Inject

@AndroidEntryPoint
class MainActivity : ComponentActivity() {

    @Inject
    lateinit var tourManager: TourManager

    @Inject
    lateinit var audioPlayer: AudioPlayer

    @Inject
    lateinit var tourConfigRepository: TourConfigRepository

    @Inject
    lateinit var masterTourRepository: MasterTourRepository

    private val viewModel: MainViewModel by viewModels()

    private var hasAudioPermission by mutableStateOf(false)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Keep screen on during the entire app lifecycle for service droid use
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        val permissionLauncher = registerForActivityResult(
            ActivityResultContracts.RequestPermission()
        ) { isGranted ->
            hasAudioPermission = isGranted
        }
        
        permissionLauncher.launch(Manifest.permission.RECORD_AUDIO)

        setContent {
            if (hasAudioPermission) {
                MainScreen(
                    tourManager = tourManager,
                    audioPlayer = audioPlayer,
                    tourConfigRepository = tourConfigRepository,
                    masterTourRepository = masterTourRepository // Pass MasterTourRepository
                )
            } else {
                Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text("RECORD_AUDIO permission is required for audio visualization.")
                }
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        audioPlayer.release()
    }
}

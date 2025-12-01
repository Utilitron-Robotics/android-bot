package com.opendroids.tourbot.di

import com.opendroids.tourbot.data.ErrorLogger
import com.opendroids.tourbot.data.TourRepository
import com.opendroids.tourbot.logic.executors.DelayExecutor
import com.opendroids.tourbot.logic.executors.NavigationExecutor
import com.opendroids.tourbot.logic.executors.SpeechExecutor
import com.opendroids.tourbot.logic.executors.WaypointTaskExecutor
import com.opendroids.tourbot.ui.audio.AudioPlayer
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object ExecutorModule {

    @Provides
    @Singleton
    fun provideNavigationExecutor(tourRepository: TourRepository, errorLogger: ErrorLogger): NavigationExecutor = NavigationExecutor(tourRepository, errorLogger)

    @Provides
    @Singleton
    fun provideSpeechExecutor(audioPlayer: AudioPlayer): SpeechExecutor = SpeechExecutor(audioPlayer)

    @Provides
    @Singleton
    fun provideDelayExecutor(): DelayExecutor = DelayExecutor()

    @Provides
    @Singleton
    fun provideWaypointTaskExecutor(
        navigationExecutor: NavigationExecutor,
        speechExecutor: SpeechExecutor
    ): WaypointTaskExecutor = WaypointTaskExecutor(navigationExecutor, speechExecutor)
}

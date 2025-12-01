package com.opendroids.tourbot.di

import android.content.Context
import com.opendroids.tourbot.data.ErrorLogger
import com.opendroids.tourbot.data.TourConfigRepository
import com.opendroids.tourbot.logic.TaskOrchestrator
import com.opendroids.tourbot.logic.TourManager
import com.opendroids.tourbot.logic.executors.*
import com.opendroids.tourbot.robot.Robot
import com.opendroids.tourbot.ui.audio.AudioPlayer
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object AppModule {

    @Provides
    @Singleton
    fun provideTourConfigRepository(@ApplicationContext context: Context): TourConfigRepository = TourConfigRepository(context)

    // Orchestrator & Manager
    @Provides
    @Singleton
    fun provideTaskOrchestrator(
        @ApplicationContext context: Context,
        waypointTaskExecutor: WaypointTaskExecutor,
        delayExecutor: DelayExecutor,
        errorLogger: ErrorLogger,
        tourConfigRepository: TourConfigRepository
    ): TaskOrchestrator = TaskOrchestrator(context, waypointTaskExecutor, delayExecutor, errorLogger, tourConfigRepository)

    @Provides
    @Singleton
    fun provideTourManager(
        tourConfigRepository: TourConfigRepository,
        taskOrchestrator: TaskOrchestrator,
        audioPlayer: AudioPlayer,
        @ApplicationContext context: Context
    ): TourManager = TourManager(tourConfigRepository, taskOrchestrator, audioPlayer, context)

    // Utilities
    @Provides
    @Singleton
    fun provideErrorLogger(): ErrorLogger = ErrorLogger()
}

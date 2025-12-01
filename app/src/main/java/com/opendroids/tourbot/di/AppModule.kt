package com.opendroids.tourbot.di

import android.content.Context
import com.opendroids.tourbot.data.ErrorLogger
import com.opendroids.tourbot.data.FakeTourRepository
import com.opendroids.tourbot.data.MasterTourRepository
import com.opendroids.tourbot.data.RealTourRepository
import com.opendroids.tourbot.data.TourConfigRepository
import com.opendroids.tourbot.data.TourRepository
import com.opendroids.tourbot.data.remote.RobotClient
import com.opendroids.tourbot.logic.TaskOrchestrator
import com.opendroids.tourbot.logic.TourManager
import com.opendroids.tourbot.logic.executors.*
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

    // Repositories
    @Provides
    @Singleton
    fun provideTourRepository(masterTourRepository: MasterTourRepository): TourRepository = masterTourRepository

    @Provides
    @Singleton
    fun provideMasterTourRepository(
        realTourRepository: RealTourRepository,
        fakeTourRepository: FakeTourRepository
    ): MasterTourRepository = MasterTourRepository(realTourRepository, fakeTourRepository)

    @Provides
    @Singleton
    fun provideRealTourRepository(robotClient: RobotClient): RealTourRepository = RealTourRepository(robotClient)

    @Provides
    @Singleton
    fun provideFakeTourRepository(): FakeTourRepository = FakeTourRepository()

    @Provides
    @Singleton
    fun provideTourConfigRepository(@ApplicationContext context: Context): TourConfigRepository = TourConfigRepository(context)

    // Executors
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

    // Orchestrator & Manager
    @Provides
    @Singleton
    fun provideTaskOrchestrator(
        @ApplicationContext context: Context,
        waypointTaskExecutor: WaypointTaskExecutor,
        speechExecutor: SpeechExecutor,
        delayExecutor: DelayExecutor,
        errorLogger: ErrorLogger,
        tourConfigRepository: TourConfigRepository
    ): TaskOrchestrator = TaskOrchestrator(context, waypointTaskExecutor, speechExecutor, delayExecutor, errorLogger, tourConfigRepository)

    @Provides
    @Singleton
    fun provideTourManager(
        tourConfigRepository: TourConfigRepository,
        taskOrchestrator: TaskOrchestrator
    ): TourManager = TourManager(tourConfigRepository, taskOrchestrator)

    // Utilities
    @Provides
    @Singleton
    fun provideErrorLogger(): ErrorLogger = ErrorLogger()
}

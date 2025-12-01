package com.opendroids.tourbot.di

import android.content.Context
import com.opendroids.tourbot.data.ErrorLogger
import com.opendroids.tourbot.data.FakeTourRepository
import com.opendroids.tourbot.data.MasterTourRepository
import com.opendroids.tourbot.data.RealTourRepository
import com.opendroids.tourbot.data.TourConfigRepository
import com.opendroids.tourbot.data.TourRepository
import com.opendroids.tourbot.data.remote.RobotClient
import com.opendroids.tourbot.data.settings.SettingsManager
import com.opendroids.tourbot.logic.TourManager
import com.opendroids.tourbot.ui.MainViewModel
import com.opendroids.tourbot.ui.audio.AudioPlayer
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object RepositoryModule {

    @Provides
    @Singleton
    fun provideFakeTourRepository(): FakeTourRepository {
        return FakeTourRepository()
    }

    @Provides
    @Singleton
    fun provideRealTourRepository(robotClient: RobotClient): RealTourRepository {
        return RealTourRepository(robotClient)
    }

    @Provides
    @Singleton
    fun provideMasterTourRepository(
        realTourRepository: RealTourRepository,
        fakeTourRepository: FakeTourRepository
    ): MasterTourRepository {
        return MasterTourRepository(realTourRepository, fakeTourRepository)
    }

    @Provides
    @Singleton
    fun provideTourRepository(
        masterTourRepository: MasterTourRepository
    ): TourRepository {
        return masterTourRepository
    }

    @Provides
    @Singleton
    fun provideTourConfigRepository(
        @ApplicationContext context: Context
    ): TourConfigRepository {
        return TourConfigRepository(context)
    }

    @Provides
    @Singleton
    fun provideErrorLogger(): ErrorLogger {
        return ErrorLogger()
    }

    @Provides
    @Singleton
    fun provideMainViewModel(
        settingsManager: SettingsManager,
        tourRepository: TourRepository,
        errorLogger: ErrorLogger
    ): MainViewModel {
        return MainViewModel(settingsManager, tourRepository, errorLogger)
    }

    @Provides
    @Singleton
    fun provideTourManager(
        @ApplicationContext context: Context,
        tourRepository: TourRepository,
        audioPlayer: AudioPlayer,
        settingsManager: SettingsManager,
        tourConfigRepository: TourConfigRepository,
        mainViewModel: MainViewModel
    ): TourManager {
        return TourManager(context, tourRepository, audioPlayer, settingsManager, tourConfigRepository, mainViewModel)
    }
}

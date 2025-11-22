package com.opendroids.tourbot.di

import com.opendroids.tourbot.data.FakeTourRepository
import com.opendroids.tourbot.data.RealTourRepository
import com.opendroids.tourbot.data.TourRepository
import dagger.Binds
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
abstract class RepositoryModule {

    // Temporarily bind the FakeTourRepository for testing
    @Binds
    @Singleton
    abstract fun bindTourRepository(
        fakeTourRepository: FakeTourRepository
    ): TourRepository

    // The RealTourRepository binding is commented out for now
    // @Binds
    // @Singleton
    // abstract fun bindRealTourRepository(
    //     realTourRepository: RealTourRepository
    // ): TourRepository
}

package com.opendroids.tourbot.di

import com.opendroids.tourbot.data.MasterTourRepository
import com.opendroids.tourbot.data.TourRepository
import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
abstract class RepositoryModule {

    @Binds
    @Singleton
    abstract fun bindTourRepository(
        masterTourRepository: MasterTourRepository
    ): TourRepository
}

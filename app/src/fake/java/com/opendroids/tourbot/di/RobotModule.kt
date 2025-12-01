package com.opendroids.tourbot.di

import com.opendroids.tourbot.robot.FakeRobot
import com.opendroids.tourbot.robot.Robot
import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent

@Module
@InstallIn(SingletonComponent::class)
abstract class RobotModule {
    @Binds
    abstract fun bindRobot(robot: FakeRobot): Robot
}

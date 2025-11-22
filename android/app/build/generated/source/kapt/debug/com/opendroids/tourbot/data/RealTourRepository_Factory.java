package com.opendroids.tourbot.data;

import com.opendroids.tourbot.data.remote.RobotClient;
import dagger.internal.DaggerGenerated;
import dagger.internal.Factory;
import dagger.internal.QualifierMetadata;
import dagger.internal.ScopeMetadata;
import javax.annotation.processing.Generated;
import javax.inject.Provider;

@ScopeMetadata
@QualifierMetadata
@DaggerGenerated
@Generated(
    value = "dagger.internal.codegen.ComponentProcessor",
    comments = "https://dagger.dev"
)
@SuppressWarnings({
    "unchecked",
    "rawtypes",
    "KotlinInternal",
    "KotlinInternalInJava",
    "cast"
})
public final class RealTourRepository_Factory implements Factory<RealTourRepository> {
  private final Provider<RobotClient> robotClientProvider;

  public RealTourRepository_Factory(Provider<RobotClient> robotClientProvider) {
    this.robotClientProvider = robotClientProvider;
  }

  @Override
  public RealTourRepository get() {
    return newInstance(robotClientProvider.get());
  }

  public static RealTourRepository_Factory create(Provider<RobotClient> robotClientProvider) {
    return new RealTourRepository_Factory(robotClientProvider);
  }

  public static RealTourRepository newInstance(RobotClient robotClient) {
    return new RealTourRepository(robotClient);
  }
}

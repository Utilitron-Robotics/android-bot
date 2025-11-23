package com.opendroids.tourbot.data.remote;

import dagger.internal.DaggerGenerated;
import dagger.internal.Factory;
import dagger.internal.QualifierMetadata;
import dagger.internal.ScopeMetadata;
import javax.annotation.processing.Generated;

@ScopeMetadata("javax.inject.Singleton")
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
public final class RobotClient_Factory implements Factory<RobotClient> {
  @Override
  public RobotClient get() {
    return newInstance();
  }

  public static RobotClient_Factory create() {
    return InstanceHolder.INSTANCE;
  }

  public static RobotClient newInstance() {
    return new RobotClient();
  }

  private static final class InstanceHolder {
    private static final RobotClient_Factory INSTANCE = new RobotClient_Factory();
  }
}

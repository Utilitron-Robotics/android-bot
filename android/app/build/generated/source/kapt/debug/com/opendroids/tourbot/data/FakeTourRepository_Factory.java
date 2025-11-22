package com.opendroids.tourbot.data;

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
public final class FakeTourRepository_Factory implements Factory<FakeTourRepository> {
  @Override
  public FakeTourRepository get() {
    return newInstance();
  }

  public static FakeTourRepository_Factory create() {
    return InstanceHolder.INSTANCE;
  }

  public static FakeTourRepository newInstance() {
    return new FakeTourRepository();
  }

  private static final class InstanceHolder {
    private static final FakeTourRepository_Factory INSTANCE = new FakeTourRepository_Factory();
  }
}

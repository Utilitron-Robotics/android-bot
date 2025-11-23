package com.opendroids.tourbot.data;

import android.content.Context;
import dagger.internal.DaggerGenerated;
import dagger.internal.Factory;
import dagger.internal.QualifierMetadata;
import dagger.internal.ScopeMetadata;
import javax.annotation.processing.Generated;
import javax.inject.Provider;

@ScopeMetadata("javax.inject.Singleton")
@QualifierMetadata("dagger.hilt.android.qualifiers.ApplicationContext")
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
public final class TourConfigRepository_Factory implements Factory<TourConfigRepository> {
  private final Provider<Context> contextProvider;

  public TourConfigRepository_Factory(Provider<Context> contextProvider) {
    this.contextProvider = contextProvider;
  }

  @Override
  public TourConfigRepository get() {
    return newInstance(contextProvider.get());
  }

  public static TourConfigRepository_Factory create(Provider<Context> contextProvider) {
    return new TourConfigRepository_Factory(contextProvider);
  }

  public static TourConfigRepository newInstance(Context context) {
    return new TourConfigRepository(context);
  }
}

package com.opendroids.tourbot.data.settings;

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
public final class SettingsManager_Factory implements Factory<SettingsManager> {
  private final Provider<Context> appContextProvider;

  public SettingsManager_Factory(Provider<Context> appContextProvider) {
    this.appContextProvider = appContextProvider;
  }

  @Override
  public SettingsManager get() {
    return newInstance(appContextProvider.get());
  }

  public static SettingsManager_Factory create(Provider<Context> appContextProvider) {
    return new SettingsManager_Factory(appContextProvider);
  }

  public static SettingsManager newInstance(Context appContext) {
    return new SettingsManager(appContext);
  }
}

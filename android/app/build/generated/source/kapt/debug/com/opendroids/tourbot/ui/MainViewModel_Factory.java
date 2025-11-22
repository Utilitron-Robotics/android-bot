package com.opendroids.tourbot.ui;

import com.opendroids.tourbot.data.TourRepository;
import com.opendroids.tourbot.data.settings.SettingsManager;
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
public final class MainViewModel_Factory implements Factory<MainViewModel> {
  private final Provider<SettingsManager> settingsManagerProvider;

  private final Provider<TourRepository> tourRepositoryProvider;

  public MainViewModel_Factory(Provider<SettingsManager> settingsManagerProvider,
      Provider<TourRepository> tourRepositoryProvider) {
    this.settingsManagerProvider = settingsManagerProvider;
    this.tourRepositoryProvider = tourRepositoryProvider;
  }

  @Override
  public MainViewModel get() {
    return newInstance(settingsManagerProvider.get(), tourRepositoryProvider.get());
  }

  public static MainViewModel_Factory create(Provider<SettingsManager> settingsManagerProvider,
      Provider<TourRepository> tourRepositoryProvider) {
    return new MainViewModel_Factory(settingsManagerProvider, tourRepositoryProvider);
  }

  public static MainViewModel newInstance(SettingsManager settingsManager,
      TourRepository tourRepository) {
    return new MainViewModel(settingsManager, tourRepository);
  }
}

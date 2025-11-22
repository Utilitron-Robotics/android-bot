package com.opendroids.tourbot.ui.settings;

import com.opendroids.tourbot.data.TourConfigRepository;
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
public final class SettingsViewModel_Factory implements Factory<SettingsViewModel> {
  private final Provider<TourConfigRepository> tourConfigRepositoryProvider;

  public SettingsViewModel_Factory(Provider<TourConfigRepository> tourConfigRepositoryProvider) {
    this.tourConfigRepositoryProvider = tourConfigRepositoryProvider;
  }

  @Override
  public SettingsViewModel get() {
    return newInstance(tourConfigRepositoryProvider.get());
  }

  public static SettingsViewModel_Factory create(
      Provider<TourConfigRepository> tourConfigRepositoryProvider) {
    return new SettingsViewModel_Factory(tourConfigRepositoryProvider);
  }

  public static SettingsViewModel newInstance(TourConfigRepository tourConfigRepository) {
    return new SettingsViewModel(tourConfigRepository);
  }
}

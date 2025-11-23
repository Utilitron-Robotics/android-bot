package com.opendroids.tourbot.logic;

import android.content.Context;
import com.opendroids.tourbot.data.TourConfigRepository;
import com.opendroids.tourbot.data.TourRepository;
import com.opendroids.tourbot.data.settings.SettingsManager;
import com.opendroids.tourbot.ui.audio.AudioPlayer;
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
public final class TourManager_Factory implements Factory<TourManager> {
  private final Provider<Context> contextProvider;

  private final Provider<TourRepository> tourRepositoryProvider;

  private final Provider<AudioPlayer> audioPlayerProvider;

  private final Provider<SettingsManager> settingsManagerProvider;

  private final Provider<TourConfigRepository> tourConfigRepositoryProvider;

  public TourManager_Factory(Provider<Context> contextProvider,
      Provider<TourRepository> tourRepositoryProvider, Provider<AudioPlayer> audioPlayerProvider,
      Provider<SettingsManager> settingsManagerProvider,
      Provider<TourConfigRepository> tourConfigRepositoryProvider) {
    this.contextProvider = contextProvider;
    this.tourRepositoryProvider = tourRepositoryProvider;
    this.audioPlayerProvider = audioPlayerProvider;
    this.settingsManagerProvider = settingsManagerProvider;
    this.tourConfigRepositoryProvider = tourConfigRepositoryProvider;
  }

  @Override
  public TourManager get() {
    return newInstance(contextProvider.get(), tourRepositoryProvider.get(), audioPlayerProvider.get(), settingsManagerProvider.get(), tourConfigRepositoryProvider.get());
  }

  public static TourManager_Factory create(Provider<Context> contextProvider,
      Provider<TourRepository> tourRepositoryProvider, Provider<AudioPlayer> audioPlayerProvider,
      Provider<SettingsManager> settingsManagerProvider,
      Provider<TourConfigRepository> tourConfigRepositoryProvider) {
    return new TourManager_Factory(contextProvider, tourRepositoryProvider, audioPlayerProvider, settingsManagerProvider, tourConfigRepositoryProvider);
  }

  public static TourManager newInstance(Context context, TourRepository tourRepository,
      AudioPlayer audioPlayer, SettingsManager settingsManager,
      TourConfigRepository tourConfigRepository) {
    return new TourManager(context, tourRepository, audioPlayer, settingsManager, tourConfigRepository);
  }
}

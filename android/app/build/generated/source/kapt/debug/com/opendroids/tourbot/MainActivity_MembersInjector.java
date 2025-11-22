package com.opendroids.tourbot;

import com.opendroids.tourbot.data.TourConfigRepository;
import com.opendroids.tourbot.logic.TourManager;
import com.opendroids.tourbot.ui.audio.AudioPlayer;
import dagger.MembersInjector;
import dagger.internal.DaggerGenerated;
import dagger.internal.InjectedFieldSignature;
import dagger.internal.QualifierMetadata;
import javax.annotation.processing.Generated;
import javax.inject.Provider;

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
public final class MainActivity_MembersInjector implements MembersInjector<MainActivity> {
  private final Provider<TourManager> tourManagerProvider;

  private final Provider<AudioPlayer> audioPlayerProvider;

  private final Provider<TourConfigRepository> tourConfigRepositoryProvider;

  public MainActivity_MembersInjector(Provider<TourManager> tourManagerProvider,
      Provider<AudioPlayer> audioPlayerProvider,
      Provider<TourConfigRepository> tourConfigRepositoryProvider) {
    this.tourManagerProvider = tourManagerProvider;
    this.audioPlayerProvider = audioPlayerProvider;
    this.tourConfigRepositoryProvider = tourConfigRepositoryProvider;
  }

  public static MembersInjector<MainActivity> create(Provider<TourManager> tourManagerProvider,
      Provider<AudioPlayer> audioPlayerProvider,
      Provider<TourConfigRepository> tourConfigRepositoryProvider) {
    return new MainActivity_MembersInjector(tourManagerProvider, audioPlayerProvider, tourConfigRepositoryProvider);
  }

  @Override
  public void injectMembers(MainActivity instance) {
    injectTourManager(instance, tourManagerProvider.get());
    injectAudioPlayer(instance, audioPlayerProvider.get());
    injectTourConfigRepository(instance, tourConfigRepositoryProvider.get());
  }

  @InjectedFieldSignature("com.opendroids.tourbot.MainActivity.tourManager")
  public static void injectTourManager(MainActivity instance, TourManager tourManager) {
    instance.tourManager = tourManager;
  }

  @InjectedFieldSignature("com.opendroids.tourbot.MainActivity.audioPlayer")
  public static void injectAudioPlayer(MainActivity instance, AudioPlayer audioPlayer) {
    instance.audioPlayer = audioPlayer;
  }

  @InjectedFieldSignature("com.opendroids.tourbot.MainActivity.tourConfigRepository")
  public static void injectTourConfigRepository(MainActivity instance,
      TourConfigRepository tourConfigRepository) {
    instance.tourConfigRepository = tourConfigRepository;
  }
}

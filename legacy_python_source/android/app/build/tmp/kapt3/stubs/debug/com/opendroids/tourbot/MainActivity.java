package com.opendroids.tourbot;

@dagger.hilt.android.AndroidEntryPoint()
@kotlin.Metadata(mv = {1, 9, 0}, k = 1, xi = 48, d1 = {"\u0000B\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\b\u0005\n\u0002\u0010\u000b\n\u0002\b\b\n\u0002\u0018\u0002\n\u0002\b\u0005\n\u0002\u0018\u0002\n\u0002\b\u0005\n\u0002\u0018\u0002\n\u0002\b\u0005\n\u0002\u0010\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0002\b\u0007\u0018\u00002\u00020\u0001B\u0005\u00a2\u0006\u0002\u0010\u0002J\u0012\u0010$\u001a\u00020%2\b\u0010&\u001a\u0004\u0018\u00010\'H\u0014J\b\u0010(\u001a\u00020%H\u0014R\u001e\u0010\u0003\u001a\u00020\u00048\u0006@\u0006X\u0087.\u00a2\u0006\u000e\n\u0000\u001a\u0004\b\u0005\u0010\u0006\"\u0004\b\u0007\u0010\bR+\u0010\u000b\u001a\u00020\n2\u0006\u0010\t\u001a\u00020\n8B@BX\u0082\u008e\u0002\u00a2\u0006\u0012\n\u0004\b\u0010\u0010\u0011\u001a\u0004\b\f\u0010\r\"\u0004\b\u000e\u0010\u000fR\u001e\u0010\u0012\u001a\u00020\u00138\u0006@\u0006X\u0087.\u00a2\u0006\u000e\n\u0000\u001a\u0004\b\u0014\u0010\u0015\"\u0004\b\u0016\u0010\u0017R\u001e\u0010\u0018\u001a\u00020\u00198\u0006@\u0006X\u0087.\u00a2\u0006\u000e\n\u0000\u001a\u0004\b\u001a\u0010\u001b\"\u0004\b\u001c\u0010\u001dR\u001b\u0010\u001e\u001a\u00020\u001f8BX\u0082\u0084\u0002\u00a2\u0006\f\n\u0004\b\"\u0010#\u001a\u0004\b \u0010!\u00a8\u0006)"}, d2 = {"Lcom/opendroids/tourbot/MainActivity;", "Landroidx/activity/ComponentActivity;", "()V", "audioPlayer", "Lcom/opendroids/tourbot/ui/audio/AudioPlayer;", "getAudioPlayer", "()Lcom/opendroids/tourbot/ui/audio/AudioPlayer;", "setAudioPlayer", "(Lcom/opendroids/tourbot/ui/audio/AudioPlayer;)V", "<set-?>", "", "hasAudioPermission", "getHasAudioPermission", "()Z", "setHasAudioPermission", "(Z)V", "hasAudioPermission$delegate", "Landroidx/compose/runtime/MutableState;", "tourConfigRepository", "Lcom/opendroids/tourbot/data/TourConfigRepository;", "getTourConfigRepository", "()Lcom/opendroids/tourbot/data/TourConfigRepository;", "setTourConfigRepository", "(Lcom/opendroids/tourbot/data/TourConfigRepository;)V", "tourManager", "Lcom/opendroids/tourbot/logic/TourManager;", "getTourManager", "()Lcom/opendroids/tourbot/logic/TourManager;", "setTourManager", "(Lcom/opendroids/tourbot/logic/TourManager;)V", "viewModel", "Lcom/opendroids/tourbot/ui/MainViewModel;", "getViewModel", "()Lcom/opendroids/tourbot/ui/MainViewModel;", "viewModel$delegate", "Lkotlin/Lazy;", "onCreate", "", "savedInstanceState", "Landroid/os/Bundle;", "onDestroy", "app_debug"})
public final class MainActivity extends androidx.activity.ComponentActivity {
    @javax.inject.Inject()
    public com.opendroids.tourbot.logic.TourManager tourManager;
    @javax.inject.Inject()
    public com.opendroids.tourbot.ui.audio.AudioPlayer audioPlayer;
    @javax.inject.Inject()
    public com.opendroids.tourbot.data.TourConfigRepository tourConfigRepository;
    @org.jetbrains.annotations.NotNull()
    private final kotlin.Lazy viewModel$delegate = null;
    @org.jetbrains.annotations.NotNull()
    private final androidx.compose.runtime.MutableState hasAudioPermission$delegate = null;
    
    public MainActivity() {
        super(0);
    }
    
    @org.jetbrains.annotations.NotNull()
    public final com.opendroids.tourbot.logic.TourManager getTourManager() {
        return null;
    }
    
    public final void setTourManager(@org.jetbrains.annotations.NotNull()
    com.opendroids.tourbot.logic.TourManager p0) {
    }
    
    @org.jetbrains.annotations.NotNull()
    public final com.opendroids.tourbot.ui.audio.AudioPlayer getAudioPlayer() {
        return null;
    }
    
    public final void setAudioPlayer(@org.jetbrains.annotations.NotNull()
    com.opendroids.tourbot.ui.audio.AudioPlayer p0) {
    }
    
    @org.jetbrains.annotations.NotNull()
    public final com.opendroids.tourbot.data.TourConfigRepository getTourConfigRepository() {
        return null;
    }
    
    public final void setTourConfigRepository(@org.jetbrains.annotations.NotNull()
    com.opendroids.tourbot.data.TourConfigRepository p0) {
    }
    
    private final com.opendroids.tourbot.ui.MainViewModel getViewModel() {
        return null;
    }
    
    private final boolean getHasAudioPermission() {
        return false;
    }
    
    private final void setHasAudioPermission(boolean p0) {
    }
    
    @java.lang.Override()
    protected void onCreate(@org.jetbrains.annotations.Nullable()
    android.os.Bundle savedInstanceState) {
    }
    
    @java.lang.Override()
    protected void onDestroy() {
    }
}
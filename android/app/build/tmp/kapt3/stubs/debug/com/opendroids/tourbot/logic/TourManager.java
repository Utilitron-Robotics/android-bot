package com.opendroids.tourbot.logic;

@javax.inject.Singleton()
@kotlin.Metadata(mv = {1, 9, 0}, k = 1, xi = 48, d1 = {"\u0000j\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0003\n\u0002\u0010 \n\u0002\u0010\u000e\n\u0002\b\u0003\n\u0002\u0010\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0007\n\u0002\u0010\u000b\n\u0002\b\u0002\b\u0007\u0018\u00002\u00020\u0001B1\b\u0007\u0012\b\b\u0001\u0010\u0002\u001a\u00020\u0003\u0012\u0006\u0010\u0004\u001a\u00020\u0005\u0012\u0006\u0010\u0006\u001a\u00020\u0007\u0012\u0006\u0010\b\u001a\u00020\t\u0012\u0006\u0010\n\u001a\u00020\u000b\u00a2\u0006\u0002\u0010\fJ\u0006\u0010\u001d\u001a\u00020\u001eJ\u0018\u0010\u001f\u001a\u0004\u0018\u00010 2\u0006\u0010!\u001a\u00020\u001aH\u0082@\u00a2\u0006\u0002\u0010\"J\u000e\u0010#\u001a\u00020\u001eH\u0082@\u00a2\u0006\u0002\u0010$J\u000e\u0010%\u001a\u00020\u001eH\u0082@\u00a2\u0006\u0002\u0010$J\u0006\u0010&\u001a\u00020\u001eJ\u0016\u0010\'\u001a\u00020(2\u0006\u0010)\u001a\u00020\u001aH\u0082@\u00a2\u0006\u0002\u0010\"R\u0014\u0010\r\u001a\b\u0012\u0004\u0012\u00020\u000f0\u000eX\u0082\u0004\u00a2\u0006\u0002\n\u0000R\u000e\u0010\u0006\u001a\u00020\u0007X\u0082\u0004\u00a2\u0006\u0002\n\u0000R\u000e\u0010\u0002\u001a\u00020\u0003X\u0082\u0004\u00a2\u0006\u0002\n\u0000R\u000e\u0010\b\u001a\u00020\tX\u0082\u0004\u00a2\u0006\u0002\n\u0000R\u000e\u0010\n\u001a\u00020\u000bX\u0082\u0004\u00a2\u0006\u0002\n\u0000R\u0010\u0010\u0010\u001a\u0004\u0018\u00010\u0011X\u0082\u000e\u00a2\u0006\u0002\n\u0000R\u000e\u0010\u0004\u001a\u00020\u0005X\u0082\u0004\u00a2\u0006\u0002\n\u0000R\u000e\u0010\u0012\u001a\u00020\u0013X\u0082\u0004\u00a2\u0006\u0002\n\u0000R\u0017\u0010\u0014\u001a\b\u0012\u0004\u0012\u00020\u000f0\u0015\u00a2\u0006\b\n\u0000\u001a\u0004\b\u0016\u0010\u0017R\u0017\u0010\u0018\u001a\b\u0012\u0004\u0012\u00020\u001a0\u0019\u00a2\u0006\b\n\u0000\u001a\u0004\b\u001b\u0010\u001c\u00a8\u0006*"}, d2 = {"Lcom/opendroids/tourbot/logic/TourManager;", "", "context", "Landroid/content/Context;", "tourRepository", "Lcom/opendroids/tourbot/data/TourRepository;", "audioPlayer", "Lcom/opendroids/tourbot/ui/audio/AudioPlayer;", "settingsManager", "Lcom/opendroids/tourbot/data/settings/SettingsManager;", "tourConfigRepository", "Lcom/opendroids/tourbot/data/TourConfigRepository;", "(Landroid/content/Context;Lcom/opendroids/tourbot/data/TourRepository;Lcom/opendroids/tourbot/ui/audio/AudioPlayer;Lcom/opendroids/tourbot/data/settings/SettingsManager;Lcom/opendroids/tourbot/data/TourConfigRepository;)V", "_tourState", "Lkotlinx/coroutines/flow/MutableStateFlow;", "Lcom/opendroids/tourbot/data/model/TourState;", "tourJob", "Lkotlinx/coroutines/Job;", "tourScope", "Lkotlinx/coroutines/CoroutineScope;", "tourState", "Lkotlinx/coroutines/flow/StateFlow;", "getTourState", "()Lkotlinx/coroutines/flow/StateFlow;", "waypointIds", "", "", "getWaypointIds", "()Ljava/util/List;", "abort", "", "createWaypoint", "Lcom/opendroids/tourbot/data/model/Waypoint;", "id", "(Ljava/lang/String;Lkotlin/coroutines/Continuation;)Ljava/lang/Object;", "returnToStart", "(Lkotlin/coroutines/Continuation;)Ljava/lang/Object;", "runTour", "startTour", "waitForArrival", "", "destinationName", "app_debug"})
public final class TourManager {
    @org.jetbrains.annotations.NotNull()
    private final android.content.Context context = null;
    @org.jetbrains.annotations.NotNull()
    private final com.opendroids.tourbot.data.TourRepository tourRepository = null;
    @org.jetbrains.annotations.NotNull()
    private final com.opendroids.tourbot.ui.audio.AudioPlayer audioPlayer = null;
    @org.jetbrains.annotations.NotNull()
    private final com.opendroids.tourbot.data.settings.SettingsManager settingsManager = null;
    @org.jetbrains.annotations.NotNull()
    private final com.opendroids.tourbot.data.TourConfigRepository tourConfigRepository = null;
    @org.jetbrains.annotations.NotNull()
    private final kotlinx.coroutines.flow.MutableStateFlow<com.opendroids.tourbot.data.model.TourState> _tourState = null;
    @org.jetbrains.annotations.NotNull()
    private final kotlinx.coroutines.flow.StateFlow<com.opendroids.tourbot.data.model.TourState> tourState = null;
    @org.jetbrains.annotations.Nullable()
    private kotlinx.coroutines.Job tourJob;
    @org.jetbrains.annotations.NotNull()
    private final kotlinx.coroutines.CoroutineScope tourScope = null;
    @org.jetbrains.annotations.NotNull()
    private final java.util.List<java.lang.String> waypointIds = null;
    
    @javax.inject.Inject()
    public TourManager(@dagger.hilt.android.qualifiers.ApplicationContext()
    @org.jetbrains.annotations.NotNull()
    android.content.Context context, @org.jetbrains.annotations.NotNull()
    com.opendroids.tourbot.data.TourRepository tourRepository, @org.jetbrains.annotations.NotNull()
    com.opendroids.tourbot.ui.audio.AudioPlayer audioPlayer, @org.jetbrains.annotations.NotNull()
    com.opendroids.tourbot.data.settings.SettingsManager settingsManager, @org.jetbrains.annotations.NotNull()
    com.opendroids.tourbot.data.TourConfigRepository tourConfigRepository) {
        super();
    }
    
    @org.jetbrains.annotations.NotNull()
    public final kotlinx.coroutines.flow.StateFlow<com.opendroids.tourbot.data.model.TourState> getTourState() {
        return null;
    }
    
    @org.jetbrains.annotations.NotNull()
    public final java.util.List<java.lang.String> getWaypointIds() {
        return null;
    }
    
    public final void startTour() {
    }
    
    public final void abort() {
    }
    
    private final java.lang.Object returnToStart(kotlin.coroutines.Continuation<? super kotlin.Unit> $completion) {
        return null;
    }
    
    private final java.lang.Object runTour(kotlin.coroutines.Continuation<? super kotlin.Unit> $completion) {
        return null;
    }
    
    private final java.lang.Object waitForArrival(java.lang.String destinationName, kotlin.coroutines.Continuation<? super java.lang.Boolean> $completion) {
        return null;
    }
    
    private final java.lang.Object createWaypoint(java.lang.String id, kotlin.coroutines.Continuation<? super com.opendroids.tourbot.data.model.Waypoint> $completion) {
        return null;
    }
}
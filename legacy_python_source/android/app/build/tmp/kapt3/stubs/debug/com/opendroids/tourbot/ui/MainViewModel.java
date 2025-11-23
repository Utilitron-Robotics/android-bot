package com.opendroids.tourbot.ui;

@kotlin.Metadata(mv = {1, 9, 0}, k = 1, xi = 48, d1 = {"\u00004\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0002\b\u0003\n\u0002\u0010\u000e\n\u0002\b\u0002\n\u0002\u0010\u0002\n\u0002\b\u0007\b\u0007\u0018\u00002\u00020\u0001B\u0017\b\u0007\u0012\u0006\u0010\u0002\u001a\u00020\u0003\u0012\u0006\u0010\u0004\u001a\u00020\u0005\u00a2\u0006\u0002\u0010\u0006J\u0006\u0010\u000f\u001a\u00020\u0010J\u000e\u0010\u0011\u001a\u00020\u00102\u0006\u0010\u0012\u001a\u00020\rJ\u0006\u0010\u0013\u001a\u00020\u0010J\u000e\u0010\u0014\u001a\u00020\u00102\u0006\u0010\u0015\u001a\u00020\rJ\u000e\u0010\u0016\u001a\u00020\u00102\u0006\u0010\u0012\u001a\u00020\rR\u0019\u0010\u0007\u001a\n\u0012\u0006\u0012\u0004\u0018\u00010\t0\b\u00a2\u0006\b\n\u0000\u001a\u0004\b\n\u0010\u000bR\u0017\u0010\f\u001a\b\u0012\u0004\u0012\u00020\r0\b\u00a2\u0006\b\n\u0000\u001a\u0004\b\u000e\u0010\u000bR\u000e\u0010\u0002\u001a\u00020\u0003X\u0082\u0004\u00a2\u0006\u0002\n\u0000R\u000e\u0010\u0004\u001a\u00020\u0005X\u0082\u0004\u00a2\u0006\u0002\n\u0000\u00a8\u0006\u0017"}, d2 = {"Lcom/opendroids/tourbot/ui/MainViewModel;", "Landroidx/lifecycle/ViewModel;", "settingsManager", "Lcom/opendroids/tourbot/data/settings/SettingsManager;", "tourRepository", "Lcom/opendroids/tourbot/data/TourRepository;", "(Lcom/opendroids/tourbot/data/settings/SettingsManager;Lcom/opendroids/tourbot/data/TourRepository;)V", "robotStatus", "Lkotlinx/coroutines/flow/StateFlow;", "Lcom/opendroids/tourbot/data/remote/model/RobotStatusMessage;", "getRobotStatus", "()Lkotlinx/coroutines/flow/StateFlow;", "robotUrl", "", "getRobotUrl", "cancelNavigation", "", "connectToRobot", "url", "disconnectFromRobot", "goToPoi", "poi", "setRobotUrl", "app_debug"})
@dagger.hilt.android.lifecycle.HiltViewModel()
public final class MainViewModel extends androidx.lifecycle.ViewModel {
    @org.jetbrains.annotations.NotNull()
    private final com.opendroids.tourbot.data.settings.SettingsManager settingsManager = null;
    @org.jetbrains.annotations.NotNull()
    private final com.opendroids.tourbot.data.TourRepository tourRepository = null;
    @org.jetbrains.annotations.NotNull()
    private final kotlinx.coroutines.flow.StateFlow<java.lang.String> robotUrl = null;
    @org.jetbrains.annotations.NotNull()
    private final kotlinx.coroutines.flow.StateFlow<com.opendroids.tourbot.data.remote.model.RobotStatusMessage> robotStatus = null;
    
    @javax.inject.Inject()
    public MainViewModel(@org.jetbrains.annotations.NotNull()
    com.opendroids.tourbot.data.settings.SettingsManager settingsManager, @org.jetbrains.annotations.NotNull()
    com.opendroids.tourbot.data.TourRepository tourRepository) {
        super();
    }
    
    @org.jetbrains.annotations.NotNull()
    public final kotlinx.coroutines.flow.StateFlow<java.lang.String> getRobotUrl() {
        return null;
    }
    
    @org.jetbrains.annotations.NotNull()
    public final kotlinx.coroutines.flow.StateFlow<com.opendroids.tourbot.data.remote.model.RobotStatusMessage> getRobotStatus() {
        return null;
    }
    
    public final void setRobotUrl(@org.jetbrains.annotations.NotNull()
    java.lang.String url) {
    }
    
    public final void connectToRobot(@org.jetbrains.annotations.NotNull()
    java.lang.String url) {
    }
    
    public final void disconnectFromRobot() {
    }
    
    public final void goToPoi(@org.jetbrains.annotations.NotNull()
    java.lang.String poi) {
    }
    
    public final void cancelNavigation() {
    }
}
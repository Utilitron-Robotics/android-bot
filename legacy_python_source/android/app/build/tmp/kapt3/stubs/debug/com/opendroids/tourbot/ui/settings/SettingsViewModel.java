package com.opendroids.tourbot.ui.settings;

@kotlin.Metadata(mv = {1, 9, 0}, k = 1, xi = 48, d1 = {"\u0000&\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\u0010\b\n\u0002\b\u0003\n\u0002\u0010\u0002\n\u0002\b\u0002\b\u0007\u0018\u00002\u00020\u0001B\u000f\b\u0007\u0012\u0006\u0010\u0002\u001a\u00020\u0003\u00a2\u0006\u0002\u0010\u0004J\u000e\u0010\n\u001a\u00020\u000b2\u0006\u0010\f\u001a\u00020\u0007R\u0017\u0010\u0005\u001a\b\u0012\u0004\u0012\u00020\u00070\u0006\u00a2\u0006\b\n\u0000\u001a\u0004\b\b\u0010\tR\u000e\u0010\u0002\u001a\u00020\u0003X\u0082\u0004\u00a2\u0006\u0002\n\u0000\u00a8\u0006\r"}, d2 = {"Lcom/opendroids/tourbot/ui/settings/SettingsViewModel;", "Landroidx/lifecycle/ViewModel;", "tourConfigRepository", "Lcom/opendroids/tourbot/data/TourConfigRepository;", "(Lcom/opendroids/tourbot/data/TourConfigRepository;)V", "preSpeakDelay", "Lkotlinx/coroutines/flow/StateFlow;", "", "getPreSpeakDelay", "()Lkotlinx/coroutines/flow/StateFlow;", "setPreSpeakDelay", "", "delayMs", "app_debug"})
@dagger.hilt.android.lifecycle.HiltViewModel()
public final class SettingsViewModel extends androidx.lifecycle.ViewModel {
    @org.jetbrains.annotations.NotNull()
    private final com.opendroids.tourbot.data.TourConfigRepository tourConfigRepository = null;
    @org.jetbrains.annotations.NotNull()
    private final kotlinx.coroutines.flow.StateFlow<java.lang.Integer> preSpeakDelay = null;
    
    @javax.inject.Inject()
    public SettingsViewModel(@org.jetbrains.annotations.NotNull()
    com.opendroids.tourbot.data.TourConfigRepository tourConfigRepository) {
        super();
    }
    
    @org.jetbrains.annotations.NotNull()
    public final kotlinx.coroutines.flow.StateFlow<java.lang.Integer> getPreSpeakDelay() {
        return null;
    }
    
    public final void setPreSpeakDelay(int delayMs) {
    }
}
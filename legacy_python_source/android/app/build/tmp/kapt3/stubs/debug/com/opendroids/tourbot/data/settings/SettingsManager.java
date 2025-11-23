package com.opendroids.tourbot.data.settings;

@javax.inject.Singleton()
@kotlin.Metadata(mv = {1, 9, 0}, k = 1, xi = 48, d1 = {"\u00000\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\u0010\u000e\n\u0002\b\u0003\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0010\u0002\n\u0002\b\u0004\b\u0007\u0018\u0000 \u00112\u00020\u0001:\u0001\u0011B\u0011\b\u0007\u0012\b\b\u0001\u0010\u0002\u001a\u00020\u0003\u00a2\u0006\u0002\u0010\u0004J\u0016\u0010\r\u001a\u00020\u000e2\u0006\u0010\u000f\u001a\u00020\u0007H\u0086@\u00a2\u0006\u0002\u0010\u0010R\u0017\u0010\u0005\u001a\b\u0012\u0004\u0012\u00020\u00070\u0006\u00a2\u0006\b\n\u0000\u001a\u0004\b\b\u0010\tR\u0014\u0010\n\u001a\b\u0012\u0004\u0012\u00020\f0\u000bX\u0082\u0004\u00a2\u0006\u0002\n\u0000\u00a8\u0006\u0012"}, d2 = {"Lcom/opendroids/tourbot/data/settings/SettingsManager;", "", "appContext", "Landroid/content/Context;", "(Landroid/content/Context;)V", "robotUrl", "Lkotlinx/coroutines/flow/Flow;", "", "getRobotUrl", "()Lkotlinx/coroutines/flow/Flow;", "settingsDataStore", "Landroidx/datastore/core/DataStore;", "Landroidx/datastore/preferences/core/Preferences;", "setRobotUrl", "", "url", "(Ljava/lang/String;Lkotlin/coroutines/Continuation;)Ljava/lang/Object;", "Companion", "app_debug"})
public final class SettingsManager {
    @org.jetbrains.annotations.NotNull()
    private final androidx.datastore.core.DataStore<androidx.datastore.preferences.core.Preferences> settingsDataStore = null;
    @org.jetbrains.annotations.NotNull()
    private final kotlinx.coroutines.flow.Flow<java.lang.String> robotUrl = null;
    @org.jetbrains.annotations.NotNull()
    private static final androidx.datastore.preferences.core.Preferences.Key<java.lang.String> KEY_ROBOT_URL = null;
    @org.jetbrains.annotations.NotNull()
    public static final com.opendroids.tourbot.data.settings.SettingsManager.Companion Companion = null;
    
    @javax.inject.Inject()
    public SettingsManager(@dagger.hilt.android.qualifiers.ApplicationContext()
    @org.jetbrains.annotations.NotNull()
    android.content.Context appContext) {
        super();
    }
    
    @org.jetbrains.annotations.NotNull()
    public final kotlinx.coroutines.flow.Flow<java.lang.String> getRobotUrl() {
        return null;
    }
    
    @org.jetbrains.annotations.Nullable()
    public final java.lang.Object setRobotUrl(@org.jetbrains.annotations.NotNull()
    java.lang.String url, @org.jetbrains.annotations.NotNull()
    kotlin.coroutines.Continuation<? super kotlin.Unit> $completion) {
        return null;
    }
    
    @kotlin.Metadata(mv = {1, 9, 0}, k = 1, xi = 48, d1 = {"\u0000\u0016\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\u0010\u000e\n\u0000\b\u0086\u0003\u0018\u00002\u00020\u0001B\u0007\b\u0002\u00a2\u0006\u0002\u0010\u0002R\u0014\u0010\u0003\u001a\b\u0012\u0004\u0012\u00020\u00050\u0004X\u0082\u0004\u00a2\u0006\u0002\n\u0000\u00a8\u0006\u0006"}, d2 = {"Lcom/opendroids/tourbot/data/settings/SettingsManager$Companion;", "", "()V", "KEY_ROBOT_URL", "Landroidx/datastore/preferences/core/Preferences$Key;", "", "app_debug"})
    public static final class Companion {
        
        private Companion() {
            super();
        }
    }
}
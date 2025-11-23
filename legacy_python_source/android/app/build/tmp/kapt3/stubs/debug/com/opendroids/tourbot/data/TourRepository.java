package com.opendroids.tourbot.data;

@kotlin.Metadata(mv = {1, 9, 0}, k = 1, xi = 48, d1 = {"\u0000,\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\u0002\n\u0002\b\u0003\n\u0002\u0010\u000e\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\u0010\u0007\n\u0002\b\u0004\n\u0002\u0018\u0002\n\u0000\bf\u0018\u00002\u00020\u0001J\u000e\u0010\u0002\u001a\u00020\u0003H\u00a6@\u00a2\u0006\u0002\u0010\u0004J\u0010\u0010\u0005\u001a\u00020\u00032\u0006\u0010\u0006\u001a\u00020\u0007H&J\b\u0010\b\u001a\u00020\u0003H&J\u000e\u0010\t\u001a\b\u0012\u0004\u0012\u00020\u000b0\nH&J\u0016\u0010\f\u001a\u00020\u00032\u0006\u0010\r\u001a\u00020\u0007H\u00a6@\u00a2\u0006\u0002\u0010\u000eJ\u000e\u0010\u000f\u001a\b\u0012\u0004\u0012\u00020\u00100\nH&\u00a8\u0006\u0011"}, d2 = {"Lcom/opendroids/tourbot/data/TourRepository;", "", "cancelNavigation", "", "(Lkotlin/coroutines/Continuation;)Ljava/lang/Object;", "connect", "url", "", "disconnect", "getBatteryLevel", "Lkotlinx/coroutines/flow/Flow;", "", "goTo", "poi", "(Ljava/lang/String;Lkotlin/coroutines/Continuation;)Ljava/lang/Object;", "observeStatus", "Lcom/opendroids/tourbot/data/remote/model/RobotStatusMessage;", "app_debug"})
public abstract interface TourRepository {
    
    public abstract void connect(@org.jetbrains.annotations.NotNull()
    java.lang.String url);
    
    public abstract void disconnect();
    
    @org.jetbrains.annotations.Nullable()
    public abstract java.lang.Object goTo(@org.jetbrains.annotations.NotNull()
    java.lang.String poi, @org.jetbrains.annotations.NotNull()
    kotlin.coroutines.Continuation<? super kotlin.Unit> $completion);
    
    @org.jetbrains.annotations.Nullable()
    public abstract java.lang.Object cancelNavigation(@org.jetbrains.annotations.NotNull()
    kotlin.coroutines.Continuation<? super kotlin.Unit> $completion);
    
    @org.jetbrains.annotations.NotNull()
    public abstract kotlinx.coroutines.flow.Flow<java.lang.Float> getBatteryLevel();
    
    @org.jetbrains.annotations.NotNull()
    public abstract kotlinx.coroutines.flow.Flow<com.opendroids.tourbot.data.remote.model.RobotStatusMessage> observeStatus();
}
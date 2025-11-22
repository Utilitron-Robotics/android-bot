package com.opendroids.tourbot.data;

@kotlin.Metadata(mv = {1, 9, 0}, k = 1, xi = 48, d1 = {"\u00004\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0010\u0002\n\u0002\b\u0003\n\u0002\u0010\u000e\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\u0010\u0007\n\u0002\b\u0004\n\u0002\u0018\u0002\n\u0000\u0018\u00002\u00020\u0001B\u000f\b\u0007\u0012\u0006\u0010\u0002\u001a\u00020\u0003\u00a2\u0006\u0002\u0010\u0004J\u000e\u0010\u0005\u001a\u00020\u0006H\u0096@\u00a2\u0006\u0002\u0010\u0007J\u0010\u0010\b\u001a\u00020\u00062\u0006\u0010\t\u001a\u00020\nH\u0016J\b\u0010\u000b\u001a\u00020\u0006H\u0016J\u000e\u0010\f\u001a\b\u0012\u0004\u0012\u00020\u000e0\rH\u0016J\u0016\u0010\u000f\u001a\u00020\u00062\u0006\u0010\u0010\u001a\u00020\nH\u0096@\u00a2\u0006\u0002\u0010\u0011J\u000e\u0010\u0012\u001a\b\u0012\u0004\u0012\u00020\u00130\rH\u0016R\u000e\u0010\u0002\u001a\u00020\u0003X\u0082\u0004\u00a2\u0006\u0002\n\u0000\u00a8\u0006\u0014"}, d2 = {"Lcom/opendroids/tourbot/data/RealTourRepository;", "Lcom/opendroids/tourbot/data/TourRepository;", "robotClient", "Lcom/opendroids/tourbot/data/remote/RobotClient;", "(Lcom/opendroids/tourbot/data/remote/RobotClient;)V", "cancelNavigation", "", "(Lkotlin/coroutines/Continuation;)Ljava/lang/Object;", "connect", "url", "", "disconnect", "getBatteryLevel", "Lkotlinx/coroutines/flow/Flow;", "", "goTo", "poi", "(Ljava/lang/String;Lkotlin/coroutines/Continuation;)Ljava/lang/Object;", "observeStatus", "Lcom/opendroids/tourbot/data/remote/model/RobotStatusMessage;", "app_debug"})
public final class RealTourRepository implements com.opendroids.tourbot.data.TourRepository {
    @org.jetbrains.annotations.NotNull()
    private final com.opendroids.tourbot.data.remote.RobotClient robotClient = null;
    
    @javax.inject.Inject()
    public RealTourRepository(@org.jetbrains.annotations.NotNull()
    com.opendroids.tourbot.data.remote.RobotClient robotClient) {
        super();
    }
    
    @java.lang.Override()
    public void connect(@org.jetbrains.annotations.NotNull()
    java.lang.String url) {
    }
    
    @java.lang.Override()
    public void disconnect() {
    }
    
    @java.lang.Override()
    @org.jetbrains.annotations.Nullable()
    public java.lang.Object goTo(@org.jetbrains.annotations.NotNull()
    java.lang.String poi, @org.jetbrains.annotations.NotNull()
    kotlin.coroutines.Continuation<? super kotlin.Unit> $completion) {
        return null;
    }
    
    @java.lang.Override()
    @org.jetbrains.annotations.Nullable()
    public java.lang.Object cancelNavigation(@org.jetbrains.annotations.NotNull()
    kotlin.coroutines.Continuation<? super kotlin.Unit> $completion) {
        return null;
    }
    
    @java.lang.Override()
    @org.jetbrains.annotations.NotNull()
    public kotlinx.coroutines.flow.Flow<java.lang.Float> getBatteryLevel() {
        return null;
    }
    
    @java.lang.Override()
    @org.jetbrains.annotations.NotNull()
    public kotlinx.coroutines.flow.Flow<com.opendroids.tourbot.data.remote.model.RobotStatusMessage> observeStatus() {
        return null;
    }
}
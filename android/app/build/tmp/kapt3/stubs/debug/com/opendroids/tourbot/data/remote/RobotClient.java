package com.opendroids.tourbot.data.remote;

@javax.inject.Singleton()
@kotlin.Metadata(mv = {1, 9, 0}, k = 1, xi = 48, d1 = {"\u0000J\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0003\n\u0002\u0018\u0002\n\u0000\n\u0002\u0010\u0002\n\u0000\n\u0002\u0010\u000e\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0003\n\u0002\u0018\u0002\n\u0000\b\u0007\u0018\u00002\u00020\u0001B\u0007\b\u0007\u00a2\u0006\u0002\u0010\u0002J\u000e\u0010\u0010\u001a\u00020\u00112\u0006\u0010\u0012\u001a\u00020\u0013J\b\u0010\u0014\u001a\u00020\u0015H\u0002J\u0006\u0010\u0016\u001a\u00020\u0011J\u000e\u0010\u0017\u001a\u00020\u00112\u0006\u0010\u0018\u001a\u00020\u0019R\u0014\u0010\u0003\u001a\b\u0012\u0004\u0012\u00020\u00050\u0004X\u0082\u0004\u00a2\u0006\u0002\n\u0000R\u000e\u0010\u0006\u001a\u00020\u0007X\u0082\u0004\u00a2\u0006\u0002\n\u0000R\u000e\u0010\b\u001a\u00020\tX\u0082\u0004\u00a2\u0006\u0002\n\u0000R\u0017\u0010\n\u001a\b\u0012\u0004\u0012\u00020\u00050\u000b\u00a2\u0006\b\n\u0000\u001a\u0004\b\f\u0010\rR\u0010\u0010\u000e\u001a\u0004\u0018\u00010\u000fX\u0082\u000e\u00a2\u0006\u0002\n\u0000\u00a8\u0006\u001a"}, d2 = {"Lcom/opendroids/tourbot/data/remote/RobotClient;", "", "()V", "_messages", "Lkotlinx/coroutines/flow/MutableSharedFlow;", "Lcom/opendroids/tourbot/data/remote/model/RobotMessage;", "client", "Lokhttp3/OkHttpClient;", "json", "Lkotlinx/serialization/json/Json;", "messages", "Lkotlinx/coroutines/flow/Flow;", "getMessages", "()Lkotlinx/coroutines/flow/Flow;", "webSocket", "Lokhttp3/WebSocket;", "connect", "", "url", "", "createListener", "Lokhttp3/WebSocketListener;", "disconnect", "sendCommand", "command", "Lcom/opendroids/tourbot/data/remote/model/RobotCommand;", "app_debug"})
public final class RobotClient {
    @org.jetbrains.annotations.NotNull()
    private final okhttp3.OkHttpClient client = null;
    @org.jetbrains.annotations.Nullable()
    private okhttp3.WebSocket webSocket;
    @org.jetbrains.annotations.NotNull()
    private final kotlinx.serialization.json.Json json = null;
    @org.jetbrains.annotations.NotNull()
    private final kotlinx.coroutines.flow.MutableSharedFlow<com.opendroids.tourbot.data.remote.model.RobotMessage> _messages = null;
    @org.jetbrains.annotations.NotNull()
    private final kotlinx.coroutines.flow.Flow<com.opendroids.tourbot.data.remote.model.RobotMessage> messages = null;
    
    @javax.inject.Inject()
    public RobotClient() {
        super();
    }
    
    @org.jetbrains.annotations.NotNull()
    public final kotlinx.coroutines.flow.Flow<com.opendroids.tourbot.data.remote.model.RobotMessage> getMessages() {
        return null;
    }
    
    public final void connect(@org.jetbrains.annotations.NotNull()
    java.lang.String url) {
    }
    
    public final void disconnect() {
    }
    
    public final void sendCommand(@org.jetbrains.annotations.NotNull()
    com.opendroids.tourbot.data.remote.model.RobotCommand command) {
    }
    
    private final okhttp3.WebSocketListener createListener() {
        return null;
    }
}
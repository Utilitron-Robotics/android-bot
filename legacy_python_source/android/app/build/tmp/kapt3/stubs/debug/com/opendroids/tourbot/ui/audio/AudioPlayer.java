package com.opendroids.tourbot.ui.audio;

@javax.inject.Singleton()
@kotlin.Metadata(mv = {1, 9, 0}, k = 1, xi = 48, d1 = {"\u0000L\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\u0010\b\n\u0000\n\u0002\u0010\u000e\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0003\n\u0002\u0018\u0002\n\u0002\b\u0003\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0010\u0002\n\u0002\b\n\b\u0007\u0018\u00002\u00020\u0001B\u0011\b\u0007\u0012\b\b\u0001\u0010\u0002\u001a\u00020\u0003\u00a2\u0006\u0002\u0010\u0004J\u0016\u0010\u0018\u001a\u00020\u00192\u0006\u0010\u001a\u001a\u00020\u0007H\u0086@\u00a2\u0006\u0002\u0010\u001bJ\u0006\u0010\u001c\u001a\u00020\u0019J\u0016\u0010\u001d\u001a\u00020\u00192\u0006\u0010\u001e\u001a\u00020\tH\u0086@\u00a2\u0006\u0002\u0010\u001fJ\b\u0010 \u001a\u00020\u0019H\u0002J\u0006\u0010!\u001a\u00020\u0019J\b\u0010\"\u001a\u00020\u0019H\u0002R\u0014\u0010\u0005\u001a\b\u0012\u0004\u0012\u00020\u00070\u0006X\u0082\u0004\u00a2\u0006\u0002\n\u0000R\u0014\u0010\b\u001a\b\u0012\u0004\u0012\u00020\t0\u0006X\u0082\u0004\u00a2\u0006\u0002\n\u0000R\u0017\u0010\n\u001a\b\u0012\u0004\u0012\u00020\u00070\u000b\u00a2\u0006\b\n\u0000\u001a\u0004\b\f\u0010\rR\u0010\u0010\u000e\u001a\u0004\u0018\u00010\u000fX\u0082\u000e\u00a2\u0006\u0002\n\u0000R\u0017\u0010\u0010\u001a\b\u0012\u0004\u0012\u00020\t0\u000b\u00a2\u0006\b\n\u0000\u001a\u0004\b\u0011\u0010\rR\u000e\u0010\u0002\u001a\u00020\u0003X\u0082\u0004\u00a2\u0006\u0002\n\u0000R\u0010\u0010\u0012\u001a\u0004\u0018\u00010\u0013X\u0082\u000e\u00a2\u0006\u0002\n\u0000R\u000e\u0010\u0014\u001a\u00020\u0015X\u0082\u0004\u00a2\u0006\u0002\n\u0000R\u000e\u0010\u0016\u001a\u00020\u0017X\u0082.\u00a2\u0006\u0002\n\u0000\u00a8\u0006#"}, d2 = {"Lcom/opendroids/tourbot/ui/audio/AudioPlayer;", "", "context", "Landroid/content/Context;", "(Landroid/content/Context;)V", "_amplitude", "Lkotlinx/coroutines/flow/MutableStateFlow;", "", "_captionText", "", "amplitude", "Lkotlinx/coroutines/flow/StateFlow;", "getAmplitude", "()Lkotlinx/coroutines/flow/StateFlow;", "amplitudeJob", "Lkotlinx/coroutines/Job;", "captionText", "getCaptionText", "mediaPlayer", "Landroid/media/MediaPlayer;", "scope", "Lkotlinx/coroutines/CoroutineScope;", "tts", "Landroid/speech/tts/TextToSpeech;", "play", "", "resourceId", "(ILkotlin/coroutines/Continuation;)Ljava/lang/Object;", "release", "speak", "text", "(Ljava/lang/String;Lkotlin/coroutines/Continuation;)Ljava/lang/Object;", "startAmplitudePolling", "stop", "stopAmplitudePolling", "app_debug"})
public final class AudioPlayer {
    @org.jetbrains.annotations.NotNull()
    private final android.content.Context context = null;
    @org.jetbrains.annotations.Nullable()
    private android.media.MediaPlayer mediaPlayer;
    private android.speech.tts.TextToSpeech tts;
    @org.jetbrains.annotations.NotNull()
    private final kotlinx.coroutines.flow.MutableStateFlow<java.lang.Integer> _amplitude = null;
    @org.jetbrains.annotations.NotNull()
    private final kotlinx.coroutines.flow.StateFlow<java.lang.Integer> amplitude = null;
    @org.jetbrains.annotations.NotNull()
    private final kotlinx.coroutines.flow.MutableStateFlow<java.lang.String> _captionText = null;
    @org.jetbrains.annotations.NotNull()
    private final kotlinx.coroutines.flow.StateFlow<java.lang.String> captionText = null;
    @org.jetbrains.annotations.Nullable()
    private kotlinx.coroutines.Job amplitudeJob;
    @org.jetbrains.annotations.NotNull()
    private final kotlinx.coroutines.CoroutineScope scope = null;
    
    @javax.inject.Inject()
    public AudioPlayer(@dagger.hilt.android.qualifiers.ApplicationContext()
    @org.jetbrains.annotations.NotNull()
    android.content.Context context) {
        super();
    }
    
    @org.jetbrains.annotations.NotNull()
    public final kotlinx.coroutines.flow.StateFlow<java.lang.Integer> getAmplitude() {
        return null;
    }
    
    @org.jetbrains.annotations.NotNull()
    public final kotlinx.coroutines.flow.StateFlow<java.lang.String> getCaptionText() {
        return null;
    }
    
    @org.jetbrains.annotations.Nullable()
    public final java.lang.Object play(int resourceId, @org.jetbrains.annotations.NotNull()
    kotlin.coroutines.Continuation<? super kotlin.Unit> $completion) {
        return null;
    }
    
    @org.jetbrains.annotations.Nullable()
    public final java.lang.Object speak(@org.jetbrains.annotations.NotNull()
    java.lang.String text, @org.jetbrains.annotations.NotNull()
    kotlin.coroutines.Continuation<? super kotlin.Unit> $completion) {
        return null;
    }
    
    public final void stop() {
    }
    
    private final void startAmplitudePolling() {
    }
    
    private final void stopAmplitudePolling() {
    }
    
    public final void release() {
    }
}
package com.opendroids.tourbot.data.model;

/**
 * Represents the current state of the tour.
 */
@kotlin.Metadata(mv = {1, 9, 0}, k = 1, xi = 48, d1 = {"\u0000\"\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0002\b\u0006\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0000\b6\u0018\u00002\u00020\u0001:\u0005\u0003\u0004\u0005\u0006\u0007B\u0007\b\u0004\u00a2\u0006\u0002\u0010\u0002\u0082\u0001\u0005\b\t\n\u000b\f\u00a8\u0006\r"}, d2 = {"Lcom/opendroids/tourbot/data/model/TourState;", "", "()V", "Completed", "Error", "Idle", "Navigating", "Speaking", "Lcom/opendroids/tourbot/data/model/TourState$Completed;", "Lcom/opendroids/tourbot/data/model/TourState$Error;", "Lcom/opendroids/tourbot/data/model/TourState$Idle;", "Lcom/opendroids/tourbot/data/model/TourState$Navigating;", "Lcom/opendroids/tourbot/data/model/TourState$Speaking;", "app_debug"})
public abstract class TourState {
    
    private TourState() {
        super();
    }
    
    /**
     * The tour has been successfully completed.
     */
    @kotlin.Metadata(mv = {1, 9, 0}, k = 1, xi = 48, d1 = {"\u0000\f\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0002\b\u0002\b\u00c6\u0002\u0018\u00002\u00020\u0001B\u0007\b\u0002\u00a2\u0006\u0002\u0010\u0002\u00a8\u0006\u0003"}, d2 = {"Lcom/opendroids/tourbot/data/model/TourState$Completed;", "Lcom/opendroids/tourbot/data/model/TourState;", "()V", "app_debug"})
    public static final class Completed extends com.opendroids.tourbot.data.model.TourState {
        @org.jetbrains.annotations.NotNull()
        public static final com.opendroids.tourbot.data.model.TourState.Completed INSTANCE = null;
        
        private Completed() {
        }
    }
    
    /**
     * An error occurred during the tour.
     * @property message The error message describing what went wrong.
     */
    @kotlin.Metadata(mv = {1, 9, 0}, k = 1, xi = 48, d1 = {"\u0000&\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0006\n\u0002\u0010\u000b\n\u0000\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\b\n\u0002\b\u0002\b\u0086\b\u0018\u00002\u00020\u0001B\r\u0012\u0006\u0010\u0002\u001a\u00020\u0003\u00a2\u0006\u0002\u0010\u0004J\t\u0010\u0007\u001a\u00020\u0003H\u00c6\u0003J\u0013\u0010\b\u001a\u00020\u00002\b\b\u0002\u0010\u0002\u001a\u00020\u0003H\u00c6\u0001J\u0013\u0010\t\u001a\u00020\n2\b\u0010\u000b\u001a\u0004\u0018\u00010\fH\u00d6\u0003J\t\u0010\r\u001a\u00020\u000eH\u00d6\u0001J\t\u0010\u000f\u001a\u00020\u0003H\u00d6\u0001R\u0011\u0010\u0002\u001a\u00020\u0003\u00a2\u0006\b\n\u0000\u001a\u0004\b\u0005\u0010\u0006\u00a8\u0006\u0010"}, d2 = {"Lcom/opendroids/tourbot/data/model/TourState$Error;", "Lcom/opendroids/tourbot/data/model/TourState;", "message", "", "(Ljava/lang/String;)V", "getMessage", "()Ljava/lang/String;", "component1", "copy", "equals", "", "other", "", "hashCode", "", "toString", "app_debug"})
    public static final class Error extends com.opendroids.tourbot.data.model.TourState {
        @org.jetbrains.annotations.NotNull()
        private final java.lang.String message = null;
        
        public Error(@org.jetbrains.annotations.NotNull()
        java.lang.String message) {
        }
        
        @org.jetbrains.annotations.NotNull()
        public final java.lang.String getMessage() {
            return null;
        }
        
        @org.jetbrains.annotations.NotNull()
        public final java.lang.String component1() {
            return null;
        }
        
        @org.jetbrains.annotations.NotNull()
        public final com.opendroids.tourbot.data.model.TourState.Error copy(@org.jetbrains.annotations.NotNull()
        java.lang.String message) {
            return null;
        }
        
        @java.lang.Override()
        public boolean equals(@org.jetbrains.annotations.Nullable()
        java.lang.Object other) {
            return false;
        }
        
        @java.lang.Override()
        public int hashCode() {
            return 0;
        }
        
        @java.lang.Override()
        @org.jetbrains.annotations.NotNull()
        public java.lang.String toString() {
            return null;
        }
    }
    
    /**
     * The robot is idle and ready to start a tour.
     */
    @kotlin.Metadata(mv = {1, 9, 0}, k = 1, xi = 48, d1 = {"\u0000\f\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0002\b\u0002\b\u00c6\u0002\u0018\u00002\u00020\u0001B\u0007\b\u0002\u00a2\u0006\u0002\u0010\u0002\u00a8\u0006\u0003"}, d2 = {"Lcom/opendroids/tourbot/data/model/TourState$Idle;", "Lcom/opendroids/tourbot/data/model/TourState;", "()V", "app_debug"})
    public static final class Idle extends com.opendroids.tourbot.data.model.TourState {
        @org.jetbrains.annotations.NotNull()
        public static final com.opendroids.tourbot.data.model.TourState.Idle INSTANCE = null;
        
        private Idle() {
        }
    }
    
    /**
     * The robot is navigating to a specific waypoint.
     * @property targetWaypoint The waypoint the robot is moving towards.
     */
    @kotlin.Metadata(mv = {1, 9, 0}, k = 1, xi = 48, d1 = {"\u0000*\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0006\n\u0002\u0010\u000b\n\u0000\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\b\n\u0000\n\u0002\u0010\u000e\n\u0000\b\u0086\b\u0018\u00002\u00020\u0001B\r\u0012\u0006\u0010\u0002\u001a\u00020\u0003\u00a2\u0006\u0002\u0010\u0004J\t\u0010\u0007\u001a\u00020\u0003H\u00c6\u0003J\u0013\u0010\b\u001a\u00020\u00002\b\b\u0002\u0010\u0002\u001a\u00020\u0003H\u00c6\u0001J\u0013\u0010\t\u001a\u00020\n2\b\u0010\u000b\u001a\u0004\u0018\u00010\fH\u00d6\u0003J\t\u0010\r\u001a\u00020\u000eH\u00d6\u0001J\t\u0010\u000f\u001a\u00020\u0010H\u00d6\u0001R\u0011\u0010\u0002\u001a\u00020\u0003\u00a2\u0006\b\n\u0000\u001a\u0004\b\u0005\u0010\u0006\u00a8\u0006\u0011"}, d2 = {"Lcom/opendroids/tourbot/data/model/TourState$Navigating;", "Lcom/opendroids/tourbot/data/model/TourState;", "targetWaypoint", "Lcom/opendroids/tourbot/data/model/Waypoint;", "(Lcom/opendroids/tourbot/data/model/Waypoint;)V", "getTargetWaypoint", "()Lcom/opendroids/tourbot/data/model/Waypoint;", "component1", "copy", "equals", "", "other", "", "hashCode", "", "toString", "", "app_debug"})
    public static final class Navigating extends com.opendroids.tourbot.data.model.TourState {
        @org.jetbrains.annotations.NotNull()
        private final com.opendroids.tourbot.data.model.Waypoint targetWaypoint = null;
        
        public Navigating(@org.jetbrains.annotations.NotNull()
        com.opendroids.tourbot.data.model.Waypoint targetWaypoint) {
        }
        
        @org.jetbrains.annotations.NotNull()
        public final com.opendroids.tourbot.data.model.Waypoint getTargetWaypoint() {
            return null;
        }
        
        @org.jetbrains.annotations.NotNull()
        public final com.opendroids.tourbot.data.model.Waypoint component1() {
            return null;
        }
        
        @org.jetbrains.annotations.NotNull()
        public final com.opendroids.tourbot.data.model.TourState.Navigating copy(@org.jetbrains.annotations.NotNull()
        com.opendroids.tourbot.data.model.Waypoint targetWaypoint) {
            return null;
        }
        
        @java.lang.Override()
        public boolean equals(@org.jetbrains.annotations.Nullable()
        java.lang.Object other) {
            return false;
        }
        
        @java.lang.Override()
        public int hashCode() {
            return 0;
        }
        
        @java.lang.Override()
        @org.jetbrains.annotations.NotNull()
        public java.lang.String toString() {
            return null;
        }
    }
    
    /**
     * The robot has arrived and is presenting the script.
     * @property currentWaypoint The waypoint where the robot is currently located.
     */
    @kotlin.Metadata(mv = {1, 9, 0}, k = 1, xi = 48, d1 = {"\u0000*\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0006\n\u0002\u0010\u000b\n\u0000\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\b\n\u0000\n\u0002\u0010\u000e\n\u0000\b\u0086\b\u0018\u00002\u00020\u0001B\r\u0012\u0006\u0010\u0002\u001a\u00020\u0003\u00a2\u0006\u0002\u0010\u0004J\t\u0010\u0007\u001a\u00020\u0003H\u00c6\u0003J\u0013\u0010\b\u001a\u00020\u00002\b\b\u0002\u0010\u0002\u001a\u00020\u0003H\u00c6\u0001J\u0013\u0010\t\u001a\u00020\n2\b\u0010\u000b\u001a\u0004\u0018\u00010\fH\u00d6\u0003J\t\u0010\r\u001a\u00020\u000eH\u00d6\u0001J\t\u0010\u000f\u001a\u00020\u0010H\u00d6\u0001R\u0011\u0010\u0002\u001a\u00020\u0003\u00a2\u0006\b\n\u0000\u001a\u0004\b\u0005\u0010\u0006\u00a8\u0006\u0011"}, d2 = {"Lcom/opendroids/tourbot/data/model/TourState$Speaking;", "Lcom/opendroids/tourbot/data/model/TourState;", "currentWaypoint", "Lcom/opendroids/tourbot/data/model/Waypoint;", "(Lcom/opendroids/tourbot/data/model/Waypoint;)V", "getCurrentWaypoint", "()Lcom/opendroids/tourbot/data/model/Waypoint;", "component1", "copy", "equals", "", "other", "", "hashCode", "", "toString", "", "app_debug"})
    public static final class Speaking extends com.opendroids.tourbot.data.model.TourState {
        @org.jetbrains.annotations.NotNull()
        private final com.opendroids.tourbot.data.model.Waypoint currentWaypoint = null;
        
        public Speaking(@org.jetbrains.annotations.NotNull()
        com.opendroids.tourbot.data.model.Waypoint currentWaypoint) {
        }
        
        @org.jetbrains.annotations.NotNull()
        public final com.opendroids.tourbot.data.model.Waypoint getCurrentWaypoint() {
            return null;
        }
        
        @org.jetbrains.annotations.NotNull()
        public final com.opendroids.tourbot.data.model.Waypoint component1() {
            return null;
        }
        
        @org.jetbrains.annotations.NotNull()
        public final com.opendroids.tourbot.data.model.TourState.Speaking copy(@org.jetbrains.annotations.NotNull()
        com.opendroids.tourbot.data.model.Waypoint currentWaypoint) {
            return null;
        }
        
        @java.lang.Override()
        public boolean equals(@org.jetbrains.annotations.Nullable()
        java.lang.Object other) {
            return false;
        }
        
        @java.lang.Override()
        public int hashCode() {
            return 0;
        }
        
        @java.lang.Override()
        @org.jetbrains.annotations.NotNull()
        public java.lang.String toString() {
            return null;
        }
    }
}
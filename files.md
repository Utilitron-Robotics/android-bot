# Project Files

## `app/src/main/java/com/opendroids/tourbot/di/AppModule.kt`

This file contains the Dagger Hilt module for providing application-level dependencies.

### `AppModule` object

-   **`provideTourRepository(masterTourRepository: MasterTourRepository): TourRepository`**: Provides a `TourRepository` instance.
-   **`provideMasterTourRepository(realTourRepository: RealTourRepository, fakeTourRepository: FakeTourRepository): MasterTourRepository`**: Provides a `MasterTourRepository` instance.
-   **`provideRealTourRepository(robotClient: RobotClient): RealTourRepository`**: Provides a `RealTourRepository` instance.
-   **`provideFakeTourRepository(): FakeTourRepository`**: Provides a `FakeTourRepository` instance.
-   **`provideTourConfigRepository(@ApplicationContext context: Context): TourConfigRepository`**: Provides a `TourConfigRepository` instance.
-   **`provideTaskOrchestrator(...)`**: Provides a `TaskOrchestrator` instance.
-   **`provideTourManager(...)`**: Provides a `TourManager` instance.
-   **`provideErrorLogger(): ErrorLogger`**: Provides an `ErrorLogger` instance.

## `app/src/main/java/com/opendroids/tourbot/di/NetworkModule.kt`

This file contains the Dagger Hilt module for providing network-related dependencies.

### `NetworkModule` object

-   **`provideOkHttpClient(): OkHttpClient`**: Provides an `OkHttpClient` instance configured for WebSockets.
-   **`provideJson(): Json`**: Provides a `Json` instance for serialization/deserialization.

## `app/src/main/java/com/opendroids/tourbot/di/ExecutorModule.kt`

This file contains the Dagger Hilt module for providing task executor dependencies.

### `ExecutorModule` object

-   **`provideNavigationExecutor(tourRepository: TourRepository, errorLogger: ErrorLogger): NavigationExecutor`**: Provides a `NavigationExecutor` instance.
-   **`provideSpeechExecutor(audioPlayer: AudioPlayer): SpeechExecutor`**: Provides a `SpeechExecutor` instance.
-   **`provideDelayExecutor(): DelayExecutor`**: Provides a `DelayExecutor` instance.
-   **`provideWaypointTaskExecutor(navigationExecutor: NavigationExecutor, speechExecutor: SpeechExecutor): WaypointTaskExecutor`**: Provides a `WaypointTaskExecutor` instance.

## `app/src/main/java/com/opendroids/tourbot/ui/MainScreen.kt`

This file contains the main screen of the application.

### `MainScreen` composable

-   **`MainScreen(audioPlayer: AudioPlayer, viewModel: MainViewModel)`**: The main composable function for the screen. It observes the view model's state and displays the UI accordingly.

### `ConnectionStatusIndicator` composable

-   **`ConnectionStatusIndicator(connectionStatus: ConnectionStatus)`**: A composable that displays the current connection status.

### `NerdStatsOverlay` composable

-   **`NerdStatsOverlay(...)`**: A composable that displays debug information.

## `app/src/main/java/com/opendroids/tourbot/ui/MainViewModel.kt`

This file contains the view model for the main screen.

### `MainViewModel` class

-   **`tourState: StateFlow<TourState>`**: A flow that emits the current state of the tour.
-   **`waypointIds: StateFlow<List<String>>`**: A flow that emits the list of waypoint IDs.
-   **`robotStatus: StateFlow<RobotStatusMessage?>`**: A flow that emits the current status of the robot.
-   **`isInTestMode: StateFlow<Boolean>`**: A flow that emits whether the app is in test mode.
-   **`homeWaypointId: StateFlow<String>`**: A flow that emits the ID of the home waypoint.
-   **`connectionStatus: StateFlow<ConnectionStatus>`**: A flow that emits the current connection status.
-   **`showTestModeDialog: StateFlow<Boolean>`**: A flow that emits whether to show the test mode dialog.
-   **`robotUrl: StateFlow<String>`**: A flow that emits the URL of the robot.
-   **`showNerdData: StateFlow<Boolean>`**: A flow that emits whether to show the nerd data overlay.
-   **`errors: StateFlow<List<Pair<String, Throwable?>>>`**: A flow that emits a list of errors.
-   **`setRobotUrl(url: String)`**: Sets the URL of the robot.
-   **`setHomeWaypoint(waypointId: String)`**: Sets the home waypoint.
-   **`onShowNerdDataChange(show: Boolean)`**: Sets whether to show the nerd data overlay.
-   **`startTour()`**: Starts the tour.
-   **`abortTour()`**: Aborts the tour.
-   **`logError(message: String, throwable: Throwable?)`**: Logs an error.
-   **`clearErrors()`**: Clears all errors.
-   **`connect()`**: Connects to the robot.
-   **`setTestMode(isTest: Boolean)`**: Sets whether the app is in test mode.
-   **`dismissTestModeDialog()`**: Dismisses the test mode dialog.

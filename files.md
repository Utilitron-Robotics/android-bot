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

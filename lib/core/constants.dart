/// System-wide constants for the Overpowered Errand Engine
class AppConstants {
  // Geofencing parameters (docs/NOTES.md & docs/Architecture.md)
  // The inner ring is each store's own geofence_radius_meters; the outer exit
  // ring is that radius scaled by this ratio (40m -> 80m by default).
  static const double innerArrivalRadiusMeters = 40.0;
  static const double outerExitRadiusMeters = 80.0;
  static const double outerToInnerRadiusRatio = outerExitRadiusMeters / innerArrivalRadiusMeters;
  static const int entryDwellTimeSeconds = 120;
  static const int exitGracePeriodSeconds = 180;
  static const double maxGpsHorizontalAccuracyMeters = 30.0;

  // Spatial Matrix & Routing parameters
  static const double roadTortuosityFactor = 1.28;
  static const double averageUrbanSpeedMetersPerSec = 11.1; // ~40 km/h
  static const double displacementThresholdMeters = 500.0;
  static const int geohashPrecision = 6;
  static const int matrixCacheTtlDays = 7;

  // VRPTW objective weights. Every term is expressed in "equivalent seconds"
  // so travel time, waiting, thermal decay and preference trade off directly.
  //
  // gamma: cost per perishable item per second it is carried before reaching
  // home. 0.5 means carrying one tub of ice cream for 10 extra minutes costs
  // the same as 5 extra minutes of driving.
  static const double thermalDecayPenaltyGamma = 0.5;
  // beta: extra cost per second spent waiting for a store to open (on top of
  // the waiting time itself, which already counts as elapsed time).
  static const double earlyArrivalWaitPenaltyBeta = 0.5;
  // How many seconds of extra travel a fully-confident store preference is
  // worth compared to a store the user has never bought that category at.
  static const double storePreferenceWeightSeconds = 600.0;
  // Candidate stores whose learned confidence trails the favourite store for
  // that category by more than this margin are not considered at all.
  static const double storePreferenceCutoffMargin = 0.35;
  // Penalty per second of lateness when time windows have to be relaxed.
  static const double lateArrivalPenaltyPerSecond = 50.0;
  // Exact dynamic-programming solve is used up to this many distinct tasks;
  // larger lists fall back to the insertion + 2-opt heuristic.
  static const int exactSolverMaxTasks = 12;

  // Layout Learning parameters
  static const double walkOrderDecaySigma = 300.0; // 5 min decay window
  static const double walkOrderMaxDeltaSeconds = 1800.0; // 30 min max link
  // Minimum accumulated evidence for a precedence edge to influence sorting.
  static const double walkOrderConfidenceThreshold = 0.1;

  // Home Assistant sync
  static const String defaultHaEntityId = 'todo.shopping_list';
  static const int defaultWsPort = 8123;
  static const int maxRetryDelayMs = 30000;
  static const int baseRetryDelayMs = 1000;
  static const int maxMutationRetries = 5;
}

/// System-wide constants for the Overpowered Errand Engine
class AppConstants {
  // Geofencing parameters (docs/NOTES.md & docs/Architecture.md)
  static const double innerArrivalRadiusMeters = 40.0;
  static const double outerExitRadiusMeters = 80.0;
  static const int entryDwellTimeSeconds = 120;
  static const int exitGracePeriodSeconds = 180;
  static const double maxGpsHorizontalAccuracyMeters = 30.0;

  // Spatial Matrix & Routing parameters
  static const double roadTortuosityFactor = 1.28;
  static const double averageUrbanSpeedMetersPerSec = 11.1; // ~40 km/h
  static const double displacementThresholdMeters = 500.0;
  static const int geohashPrecision = 6;
  static const int matrixCacheTtlDays = 7;

  // Perishable thermal penalty weight
  static const double thermalDecayPenaltyGamma = 250.0;

  // Layout Learning parameters
  static const double walkOrderDecaySigma = 300.0; // 5 min decay window
  static const double walkOrderMaxDeltaSeconds = 1800.0; // 30 min max link
  static const double walkOrderConfidenceThreshold = 0.1;

  // Home Assistant sync
  static const String defaultHaEntityId = 'todo.shopping_list';
  static const int defaultWsPort = 8123;
  static const int maxRetryDelayMs = 30000;
  static const int baseRetryDelayMs = 1000;
}

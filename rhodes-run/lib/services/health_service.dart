// Health Connect integration for step counting and fitness data

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

/// Health data service - reads steps from Health Connect (Android) or HealthKit (iOS)
class HealthService {
  static final HealthService instance = HealthService._();
  HealthService._();

  final Health _health = Health();

  int _stepsToday = 0;
  int _stepsGoal = 10000;
  bool _isAuthorized = false;
  // ignore: unused_field
  DateTime? _lastSync;

  // Additional health metrics
  double _caloriesToday = 0;
  double _distanceToday = 0; // in meters
  int _activeMinutesToday = 0;

  final _stepsController = StreamController<int>.broadcast();
  Stream<int> get stepsStream => _stepsController.stream;

  int get stepsToday => _stepsToday;
  int get stepsGoal => _stepsGoal;
  bool get isAuthorized => _isAuthorized;
  double get progress => _stepsToday / _stepsGoal;
  double get caloriesToday => _caloriesToday;
  double get distanceToday => _distanceToday;
  int get activeMinutesToday => _activeMinutesToday;

  /// Health data types we want to read
  static final List<HealthDataType> _readTypes = [
    HealthDataType.STEPS,
    HealthDataType.DISTANCE_DELTA,
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.WORKOUT,
  ];

  /// Health data types we want to write
  static final List<HealthDataType> _writeTypes = [
    HealthDataType.STEPS,
    HealthDataType.DISTANCE_DELTA,
    HealthDataType.WORKOUT,
  ];

  /// Initialize health service
  Future<void> initialize() async {
    debugPrint('[HealthService] Initializing...');

    // Configure health package
    await _health.configure();

    // Check if Health Connect is available (Android 14+)
    if (Platform.isAndroid) {
      final status = await _health.getHealthConnectSdkStatus();
      debugPrint('[HealthService] Health Connect status: $status');

      if (status == HealthConnectSdkStatus.sdkUnavailable) {
        debugPrint('[HealthService] Health Connect not available');
      }
    }
  }

  /// Request authorization to read/write health data
  Future<bool> requestAuthorization() async {
    try {
      // Request permissions
      final permissions = _readTypes.map((e) => HealthDataAccess.READ).toList()
        ..addAll(_writeTypes.map((e) => HealthDataAccess.READ_WRITE));

      final types = [..._readTypes, ..._writeTypes];

      _isAuthorized = await _health.requestAuthorization(
        types,
        permissions: permissions,
      );

      debugPrint('[HealthService] Authorization: $_isAuthorized');

      if (_isAuthorized) {
        // Fetch initial data
        await fetchStepsToday();
      }

      return _isAuthorized;
    } catch (e) {
      debugPrint('[HealthService] Authorization error: $e');
      _isAuthorized = false;
      return false;
    }
  }

  /// Fetch today's health data from Health Connect
  Future<int> fetchStepsToday() async {
    if (!_isAuthorized) {
      final auth = await requestAuthorization();
      if (!auth) return _stepsToday;
    }

    try {
      final now = DateTime.now();
      final midnight = DateTime(now.year, now.month, now.day);

      // Get steps
      final steps = await _health.getTotalStepsInInterval(midnight, now);
      _stepsToday = steps ?? 0;

      // Get other health data
      final healthData = await _health.getHealthDataFromTypes(
        types: [
          HealthDataType.DISTANCE_DELTA,
          HealthDataType.ACTIVE_ENERGY_BURNED,
        ],
        startTime: midnight,
        endTime: now,
      );

      // Aggregate distance
      _distanceToday = 0;
      _caloriesToday = 0;

      for (final point in healthData) {
        if (point.type == HealthDataType.DISTANCE_DELTA) {
          final value = point.value;
          if (value is NumericHealthValue) {
            _distanceToday += value.numericValue.toDouble();
          }
        } else if (point.type == HealthDataType.ACTIVE_ENERGY_BURNED) {
          final value = point.value;
          if (value is NumericHealthValue) {
            _caloriesToday += value.numericValue.toDouble();
          }
        }
      }

      _lastSync = DateTime.now();
      _stepsController.add(_stepsToday);

      debugPrint('[HealthService] Fetched: $_stepsToday steps, ${_distanceToday.toStringAsFixed(0)}m, ${_caloriesToday.toStringAsFixed(0)} cal');

      return _stepsToday;
    } catch (e) {
      debugPrint('[HealthService] Fetch error: $e');
      return _stepsToday;
    }
  }

  /// Write steps to Health Connect
  Future<bool> writeSteps(int steps, {DateTime? startTime, DateTime? endTime}) async {
    if (!_isAuthorized) return false;

    try {
      final end = endTime ?? DateTime.now();
      final start = startTime ?? end.subtract(const Duration(minutes: 10));

      final success = await _health.writeHealthData(
        value: steps.toDouble(),
        type: HealthDataType.STEPS,
        startTime: start,
        endTime: end,
      );

      if (success) {
        _stepsToday += steps;
        _stepsController.add(_stepsToday);
      }

      debugPrint('[HealthService] Write steps: $success');
      return success;
    } catch (e) {
      debugPrint('[HealthService] Write error: $e');
      return false;
    }
  }

  /// Write workout to Health Connect
  Future<bool> writeWorkout({
    required DateTime startTime,
    required DateTime endTime,
    required HealthWorkoutActivityType activityType,
    double? totalDistance,
    int? totalSteps,
    double? totalEnergyBurned,
  }) async {
    if (!_isAuthorized) return false;

    try {
      final success = await _health.writeWorkoutData(
        activityType: activityType,
        start: startTime,
        end: endTime,
        totalDistance: totalDistance != null ? totalDistance.toInt() : null,
        totalEnergyBurned: totalEnergyBurned?.toInt(),
      );

      debugPrint('[HealthService] Write workout: $success');
      return success;
    } catch (e) {
      debugPrint('[HealthService] Write workout error: $e');
      return false;
    }
  }

  /// Manually add steps (for testing or manual entry)
  void addSteps(int steps) {
    _stepsToday += steps;
    _stepsController.add(_stepsToday);

    // Also write to Health Connect
    writeSteps(steps);
  }

  /// Set steps directly (from sync)
  void setSteps(int steps) {
    _stepsToday = steps;
    _stepsController.add(_stepsToday);
  }

  /// Update step goal
  void setStepGoal(int goal) {
    _stepsGoal = goal;
  }

  /// Reset for new day
  void resetDaily() {
    _stepsToday = 0;
    _distanceToday = 0;
    _caloriesToday = 0;
    _activeMinutesToday = 0;
    _stepsController.add(_stepsToday);
  }

  /// Check if Health Connect app is installed
  Future<bool> isHealthConnectAvailable() async {
    if (!Platform.isAndroid) return false;

    try {
      final status = await _health.getHealthConnectSdkStatus();
      return status == HealthConnectSdkStatus.sdkAvailable;
    } catch (e) {
      return false;
    }
  }

  /// Open Health Connect app
  Future<void> openHealthConnectSettings() async {
    if (Platform.isAndroid) {
      await _health.installHealthConnect();
    }
  }

  void dispose() {
    _stepsController.close();
  }
}

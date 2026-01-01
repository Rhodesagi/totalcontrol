// GPS location tracking for runs/walks with real geolocator integration

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/activity.dart' as models;

/// Location tracking service for GPS-based activity recording
class LocationService {
  static final LocationService instance = LocationService._();
  LocationService._();

  bool _isTracking = false;
  models.Activity? _currentActivity;
  final List<models.GpsPoint> _currentRoute = [];
  double _totalDistance = 0;
  models.GpsPoint? _lastPoint;
  StreamSubscription<Position>? _positionStream;

  final _locationController = StreamController<models.GpsPoint>.broadcast();
  final _activityController = StreamController<models.Activity>.broadcast();

  Stream<models.GpsPoint> get locationStream => _locationController.stream;
  Stream<models.Activity> get activityStream => _activityController.stream;

  bool get isTracking => _isTracking;
  models.Activity? get currentActivity => _currentActivity;
  List<models.GpsPoint> get currentRoute => List.unmodifiable(_currentRoute);
  double get totalDistance => _totalDistance;

  /// Current pace in minutes per km
  double get currentPace {
    if (_currentActivity == null || _totalDistance < 10) return 0;
    final duration = DateTime.now().difference(_currentActivity!.startTime);
    final km = _totalDistance / 1000;
    if (km < 0.01) return 0;
    return duration.inSeconds / 60 / km; // min/km
  }

  /// Current speed in km/h
  double get currentSpeed {
    if (_lastPoint == null) return 0;
    return (_lastPoint!.speed ?? 0) * 3.6; // m/s to km/h
  }

  /// Initialize location service
  Future<void> initialize() async {
    debugPrint('[LocationService] Initializing...');
    await requestPermission();
  }

  /// Request location permission
  Future<bool> requestPermission() async {
    // Check if location service is enabled
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('[LocationService] Location services disabled');
      return false;
    }

    // Check permission
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        debugPrint('[LocationService] Location permission denied');
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      debugPrint('[LocationService] Location permission permanently denied');
      return false;
    }

    // Request background location for tracking during screen off
    if (permission == LocationPermission.whileInUse) {
      final bgStatus = await Permission.locationAlways.request();
      debugPrint('[LocationService] Background location: $bgStatus');
    }

    debugPrint('[LocationService] Location permission granted');
    return true;
  }

  /// Get current location once
  Future<models.GpsPoint?> getCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      return _positionToGpsPoint(position);
    } catch (e) {
      debugPrint('[LocationService] Error getting location: $e');
      return null;
    }
  }

  /// Start tracking a new activity
  Future<models.Activity> startActivity(models.ActivityType type) async {
    if (_isTracking) {
      throw Exception('Already tracking an activity');
    }

    // Get initial location
    final initialLocation = await getCurrentLocation();

    final activity = models.Activity(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: type,
      startTime: DateTime.now(),
    );

    _currentActivity = activity;
    _currentRoute.clear();
    _totalDistance = 0;
    _lastPoint = null;
    _isTracking = true;

    // Add initial point if available
    if (initialLocation != null) {
      _currentRoute.add(initialLocation);
      _lastPoint = initialLocation;
    }

    // Start location updates
    _startLocationUpdates();

    _activityController.add(activity);
    return activity;
  }

  /// Stop tracking and finalize activity
  Future<models.Activity> stopActivity() async {
    if (!_isTracking || _currentActivity == null) {
      throw Exception('No activity in progress');
    }

    _isTracking = false;
    _stopLocationUpdates();

    final finalActivity = _currentActivity!.copyWith(
      endTime: DateTime.now(),
      route: List.from(_currentRoute),
      distanceMeters: _totalDistance,
    );

    _currentActivity = null;
    _activityController.add(finalActivity);

    return finalActivity;
  }

  /// Pause tracking
  void pauseTracking() {
    _isTracking = false;
    _stopLocationUpdates();
  }

  /// Resume tracking
  void resumeTracking() {
    if (_currentActivity == null) return;
    _isTracking = true;
    _startLocationUpdates();
  }

  void _startLocationUpdates() {
    // High accuracy settings for running/walking
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5, // Update every 5 meters
    );

    // For Android, use more specific settings
    final androidSettings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
      forceLocationManager: false,
      intervalDuration: const Duration(seconds: 1),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationText: 'Pacemeter is tracking your activity',
        notificationTitle: 'Activity in Progress',
        enableWakeLock: true,
      ),
    );

    _positionStream = Geolocator.getPositionStream(
      locationSettings: defaultTargetPlatform == TargetPlatform.android
          ? androidSettings
          : locationSettings,
    ).listen(
      (Position position) {
        if (!_isTracking) return;
        final point = _positionToGpsPoint(position);
        _onLocationUpdate(point);
      },
      onError: (error) {
        debugPrint('[LocationService] Location stream error: $error');
      },
    );
  }

  void _stopLocationUpdates() {
    _positionStream?.cancel();
    _positionStream = null;
  }

  models.GpsPoint _positionToGpsPoint(Position position) {
    return models.GpsPoint(
      latitude: position.latitude,
      longitude: position.longitude,
      altitude: position.altitude,
      speed: position.speed,
      accuracy: position.accuracy,
      timestamp: DateTime.now(),
    );
  }

  void _onLocationUpdate(models.GpsPoint point) {
    // Filter out inaccurate points
    if ((point.accuracy ?? 100) > 30) {
      debugPrint('[LocationService] Skipping inaccurate point: ${point.accuracy}m');
      return;
    }

    _currentRoute.add(point);
    _locationController.add(point);

    // Calculate distance from last point
    if (_lastPoint != null) {
      final distance = Geolocator.distanceBetween(
        _lastPoint!.latitude,
        _lastPoint!.longitude,
        point.latitude,
        point.longitude,
      );

      // Filter out GPS jumps (unrealistic distance)
      final timeDiff = point.timestamp.difference(_lastPoint!.timestamp).inSeconds;
      final maxDistance = timeDiff * 15; // Max 15 m/s (54 km/h) for running

      if (distance < maxDistance) {
        _totalDistance += distance;
      } else {
        debugPrint('[LocationService] Filtering GPS jump: $distance m in $timeDiff s');
      }
    }

    _lastPoint = point;

    // Update current activity
    if (_currentActivity != null) {
      _currentActivity = _currentActivity!.copyWith(
        route: List.from(_currentRoute),
        distanceMeters: _totalDistance,
      );
      _activityController.add(_currentActivity!);
    }
  }

  /// Calculate distance between two GPS points (Haversine formula) - backup method
  double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
  }

  void dispose() {
    _positionStream?.cancel();
    _locationController.close();
    _activityController.close();
  }
}

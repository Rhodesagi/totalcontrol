/// GPS location tracking for runs/walks

import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/activity.dart';

/// Location tracking service for GPS-based activity recording
class LocationService {
  static final LocationService instance = LocationService._();
  LocationService._();

  bool _isTracking = false;
  Activity? _currentActivity;
  final List<GpsPoint> _currentRoute = [];
  double _totalDistance = 0;
  DateTime? _lastPointTime;
  GpsPoint? _lastPoint;

  final _locationController = StreamController<GpsPoint>.broadcast();
  final _activityController = StreamController<Activity>.broadcast();

  Stream<GpsPoint> get locationStream => _locationController.stream;
  Stream<Activity> get activityStream => _activityController.stream;

  bool get isTracking => _isTracking;
  Activity? get currentActivity => _currentActivity;
  List<GpsPoint> get currentRoute => List.unmodifiable(_currentRoute);
  double get totalDistance => _totalDistance;

  /// Initialize location service
  Future<void> initialize() async {
    debugPrint('[LocationService] Initializing...');
  }

  /// Request location permission
  Future<bool> requestPermission() async {
    // TODO: Implement with geolocator package
    await Future.delayed(const Duration(milliseconds: 300));
    return true;
  }

  /// Start tracking a new activity
  Future<Activity> startActivity(ActivityType type) async {
    if (_isTracking) {
      throw Exception('Already tracking an activity');
    }

    final activity = Activity(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: type,
      startTime: DateTime.now(),
    );

    _currentActivity = activity;
    _currentRoute.clear();
    _totalDistance = 0;
    _lastPoint = null;
    _isTracking = true;

    // Start location updates
    _startLocationUpdates();

    _activityController.add(activity);
    return activity;
  }

  /// Stop tracking and finalize activity
  Future<Activity> stopActivity() async {
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

  Timer? _locationTimer;

  void _startLocationUpdates() {
    // TODO: Replace with actual GPS using geolocator package
    // For now, simulate location updates
    _locationTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!_isTracking) {
        timer.cancel();
        return;
      }
      _onLocationUpdate(_generateMockLocation());
    });
  }

  void _stopLocationUpdates() {
    _locationTimer?.cancel();
    _locationTimer = null;
  }

  void _onLocationUpdate(GpsPoint point) {
    _currentRoute.add(point);
    _locationController.add(point);

    // Calculate distance from last point
    if (_lastPoint != null) {
      final distance = _calculateDistance(
        _lastPoint!.latitude, _lastPoint!.longitude,
        point.latitude, point.longitude,
      );
      _totalDistance += distance;
    }

    _lastPoint = point;
    _lastPointTime = point.timestamp;

    // Update current activity
    if (_currentActivity != null) {
      _currentActivity = _currentActivity!.copyWith(
        route: List.from(_currentRoute),
        distanceMeters: _totalDistance,
      );
      _activityController.add(_currentActivity!);
    }
  }

  /// Calculate distance between two GPS points (Haversine formula)
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0; // Earth's radius in meters
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) * cos(_toRadians(lat2)) *
            sin(dLon / 2) * sin(dLon / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  double _toRadians(double degrees) => degrees * pi / 180;

  // Mock location for testing
  GpsPoint _generateMockLocation() {
    final baseLatitude = 37.7749; // San Francisco
    final baseLongitude = -122.4194;
    final random = Random();

    // Slight movement simulation
    final lat = baseLatitude + (_currentRoute.length * 0.0001) + (random.nextDouble() * 0.0001);
    final lng = baseLongitude + (_currentRoute.length * 0.0001) + (random.nextDouble() * 0.0001);

    return GpsPoint(
      latitude: lat,
      longitude: lng,
      altitude: 10 + random.nextDouble() * 5,
      speed: 1.5 + random.nextDouble() * 2, // Walking speed
      accuracy: 5 + random.nextDouble() * 10,
      timestamp: DateTime.now(),
    );
  }

  void dispose() {
    _locationTimer?.cancel();
    _locationController.close();
    _activityController.close();
  }
}

/*
To implement real GPS tracking, add to pubspec.yaml:

dependencies:
  geolocator: ^11.0.0
  permission_handler: ^11.0.0

Then update this service:

import 'package:geolocator/geolocator.dart';

class LocationService {
  StreamSubscription<Position>? _positionStream;

  Future<bool> requestPermission() async {
    final permission = await Geolocator.requestPermission();
    return permission == LocationPermission.always ||
           permission == LocationPermission.whileInUse;
  }

  void _startLocationUpdates() {
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10, // meters
    );

    _positionStream = Geolocator.getPositionStream(locationSettings: locationSettings)
        .listen((Position position) {
      final point = GpsPoint(
        latitude: position.latitude,
        longitude: position.longitude,
        altitude: position.altitude,
        speed: position.speed,
        accuracy: position.accuracy,
        timestamp: DateTime.now(),
      );
      _onLocationUpdate(point);
    });
  }

  void _stopLocationUpdates() {
    _positionStream?.cancel();
    _positionStream = null;
  }
}
*/

// Activity and GPS tracking models for Pacemeter

/// Types of activities
enum ActivityType {
  walk,
  run,
  bike,
  hike,
  other,
}

extension ActivityTypeExtension on ActivityType {
  String get displayName {
    switch (this) {
      case ActivityType.walk: return 'Walk';
      case ActivityType.run: return 'Run';
      case ActivityType.bike: return 'Bike';
      case ActivityType.hike: return 'Hike';
      case ActivityType.other: return 'Other';
    }
  }

  String get icon {
    switch (this) {
      case ActivityType.walk: return '🚶';
      case ActivityType.run: return '🏃';
      case ActivityType.bike: return '🚴';
      case ActivityType.hike: return '🥾';
      case ActivityType.other: return '⭐';
    }
  }
}

/// A GPS point with timestamp
class GpsPoint {
  final double latitude;
  final double longitude;
  final double? altitude;
  final double? speed;        // m/s
  final double? accuracy;     // meters
  final DateTime timestamp;

  GpsPoint({
    required this.latitude,
    required this.longitude,
    this.altitude,
    this.speed,
    this.accuracy,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'lat': latitude,
    'lng': longitude,
    'alt': altitude,
    'speed': speed,
    'acc': accuracy,
    'ts': timestamp.millisecondsSinceEpoch,
  };

  factory GpsPoint.fromJson(Map<String, dynamic> json) => GpsPoint(
    latitude: json['lat'],
    longitude: json['lng'],
    altitude: json['alt'],
    speed: json['speed'],
    accuracy: json['acc'],
    timestamp: DateTime.fromMillisecondsSinceEpoch(json['ts']),
  );
}

/// A recorded activity session
class Activity {
  final String id;
  final ActivityType type;
  final DateTime startTime;
  final DateTime? endTime;
  final List<GpsPoint> route;
  final int steps;
  final double distanceMeters;
  final int calories;
  final String? notes;

  Activity({
    required this.id,
    required this.type,
    required this.startTime,
    this.endTime,
    this.route = const [],
    this.steps = 0,
    this.distanceMeters = 0,
    this.calories = 0,
    this.notes,
  });

  Duration get duration {
    final end = endTime ?? DateTime.now();
    return end.difference(startTime);
  }

  double get distanceKm => distanceMeters / 1000;
  double get distanceMiles => distanceMeters / 1609.34;

  double get paceMinPerKm {
    if (distanceKm == 0) return 0;
    return duration.inMinutes / distanceKm;
  }

  double get avgSpeedKmh {
    if (duration.inSeconds == 0) return 0;
    return distanceKm / (duration.inSeconds / 3600);
  }

  Activity copyWith({
    String? id,
    ActivityType? type,
    DateTime? startTime,
    DateTime? endTime,
    List<GpsPoint>? route,
    int? steps,
    double? distanceMeters,
    int? calories,
    String? notes,
  }) {
    return Activity(
      id: id ?? this.id,
      type: type ?? this.type,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      route: route ?? this.route,
      steps: steps ?? this.steps,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      calories: calories ?? this.calories,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.index,
    'startTime': startTime.millisecondsSinceEpoch,
    'endTime': endTime?.millisecondsSinceEpoch,
    'route': route.map((p) => p.toJson()).toList(),
    'steps': steps,
    'distanceMeters': distanceMeters,
    'calories': calories,
    'notes': notes,
  };

  factory Activity.fromJson(Map<String, dynamic> json) => Activity(
    id: json['id'],
    type: ActivityType.values[json['type']],
    startTime: DateTime.fromMillisecondsSinceEpoch(json['startTime']),
    endTime: json['endTime'] != null
        ? DateTime.fromMillisecondsSinceEpoch(json['endTime'])
        : null,
    route: (json['route'] as List?)
        ?.map((p) => GpsPoint.fromJson(p))
        .toList() ?? [],
    steps: json['steps'] ?? 0,
    distanceMeters: (json['distanceMeters'] ?? 0).toDouble(),
    calories: json['calories'] ?? 0,
    notes: json['notes'],
  );
}

/// Daily summary
class DailySummary {
  final DateTime date;
  final int steps;
  final double distanceMeters;
  final int calories;
  final int activeMinutes;
  final List<Activity> activities;

  DailySummary({
    required this.date,
    this.steps = 0,
    this.distanceMeters = 0,
    this.calories = 0,
    this.activeMinutes = 0,
    this.activities = const [],
  });

  double get distanceKm => distanceMeters / 1000;

  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String().split('T')[0],
    'steps': steps,
    'distanceMeters': distanceMeters,
    'calories': calories,
    'activeMinutes': activeMinutes,
    'activities': activities.map((a) => a.toJson()).toList(),
  };

  factory DailySummary.fromJson(Map<String, dynamic> json) => DailySummary(
    date: DateTime.parse(json['date']),
    steps: json['steps'] ?? 0,
    distanceMeters: (json['distanceMeters'] ?? 0).toDouble(),
    calories: json['calories'] ?? 0,
    activeMinutes: json['activeMinutes'] ?? 0,
    activities: (json['activities'] as List?)
        ?.map((a) => Activity.fromJson(a))
        .toList() ?? [],
  );
}

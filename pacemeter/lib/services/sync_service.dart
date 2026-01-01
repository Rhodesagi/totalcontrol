// Firebase sync service for cross-device step/activity data

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/activity.dart';

// Sync service for Firebase/TotalControl integration
class SyncService {
  static final SyncService instance = SyncService._();
  SyncService._();

  // Firebase config
  static const String _firebaseProject = 'totalcontrol-240ec';
  static const String _fitnessCollection = 'fitness_daily';
  static const String _activitiesCollection = 'activities';

  String _userId = 'anonymous';
  bool _isConnected = false;
  DateTime? _lastSync;

  final _syncController = StreamController<bool>.broadcast();
  Stream<bool> get syncStream => _syncController.stream;

  bool get isConnected => _isConnected;
  DateTime? get lastSync => _lastSync;
  String get userId => _userId;

  /// Initialize sync service
  Future<void> initialize() async {
    debugPrint('[SyncService] Initializing...');
    // Load saved user ID
    await _loadUserId();
  }

  /// Set user ID for sync
  void setUserId(String id) {
    _userId = id;
    _saveUserId();
  }

  Future<void> _loadUserId() async {
    // TODO: Load from shared_preferences
    _userId = 'rhodes'; // Default
  }

  Future<void> _saveUserId() async {
    // TODO: Save to shared_preferences
  }

  /// Sync today's step count to Firebase
  Future<bool> syncSteps(int steps, {int? workoutMinutes, int? calories}) async {
    try {
      final today = DateTime.now();
      final dateStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final docId = '${_userId}_$dateStr';

      final data = {
        'fields': {
          'userId': {'stringValue': _userId},
          'date': {'stringValue': dateStr},
          'steps': {'integerValue': steps.toString()},
          'workout_mins': {'integerValue': (workoutMinutes ?? 0).toString()},
          'calories': {'integerValue': (calories ?? 0).toString()},
          'updatedAt': {'timestampValue': DateTime.now().toUtc().toIso8601String()},
        }
      };

      // Firebase REST API
      final url = Uri.parse(
        'https://firestore.googleapis.com/v1/projects/$_firebaseProject/databases/(default)/documents/$_fitnessCollection/$docId'
      );

      final response = await _httpPatch(url, data);

      if (response) {
        _lastSync = DateTime.now();
        _isConnected = true;
        _syncController.add(true);
        debugPrint('[SyncService] Steps synced: $steps');
        return true;
      }
    } catch (e) {
      debugPrint('[SyncService] Sync error: $e');
      _isConnected = false;
      _syncController.add(false);
    }
    return false;
  }

  /// Sync an activity to Firebase
  Future<bool> syncActivity(Activity activity) async {
    try {
      final data = {
        'fields': {
          'userId': {'stringValue': _userId},
          'type': {'integerValue': activity.type.index.toString()},
          'startTime': {'timestampValue': activity.startTime.toUtc().toIso8601String()},
          'endTime': activity.endTime != null
              ? {'timestampValue': activity.endTime!.toUtc().toIso8601String()}
              : {'nullValue': null},
          'steps': {'integerValue': activity.steps.toString()},
          'distanceMeters': {'doubleValue': activity.distanceMeters},
          'calories': {'integerValue': activity.calories.toString()},
          'durationSeconds': {'integerValue': activity.duration.inSeconds.toString()},
          // Route stored separately due to size
          'routePointCount': {'integerValue': activity.route.length.toString()},
        }
      };

      final url = Uri.parse(
        'https://firestore.googleapis.com/v1/projects/$_firebaseProject/databases/(default)/documents/$_activitiesCollection/${activity.id}'
      );

      final response = await _httpPatch(url, data);

      if (response) {
        debugPrint('[SyncService] Activity synced: ${activity.id}');
        return true;
      }
    } catch (e) {
      debugPrint('[SyncService] Activity sync error: $e');
    }
    return false;
  }

  /// Fetch today's data from Firebase (for other devices)
  Future<Map<String, dynamic>?> fetchTodayData() async {
    try {
      final today = DateTime.now();
      final dateStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final docId = '${_userId}_$dateStr';

      final url = Uri.parse(
        'https://firestore.googleapis.com/v1/projects/$_firebaseProject/databases/(default)/documents/$_fitnessCollection/$docId'
      );

      final client = HttpClient();
      final request = await client.getUrl(url);
      final response = await request.close();

      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final json = jsonDecode(body);
        final fields = json['fields'] as Map<String, dynamic>?;

        if (fields != null) {
          return {
            'steps': int.tryParse(fields['steps']?['integerValue'] ?? '0') ?? 0,
            'workout_mins': int.tryParse(fields['workout_mins']?['integerValue'] ?? '0') ?? 0,
            'calories': int.tryParse(fields['calories']?['integerValue'] ?? '0') ?? 0,
          };
        }
      }
    } catch (e) {
      debugPrint('[SyncService] Fetch error: $e');
    }
    return null;
  }

  /// HTTP PATCH helper (for Firestore updates)
  Future<bool> _httpPatch(Uri url, Map<String, dynamic> data) async {
    try {
      final client = HttpClient();
      final request = await client.patchUrl(url);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(data));
      final response = await request.close();

      // Firestore returns 200 for update, 201 for create
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      debugPrint('[SyncService] HTTP error: $e');
      return false;
    }
  }

  /// Write local file for TotalControl desktop to read
  Future<void> writeLocalSync(int steps, int workoutMins) async {
    try {
      final homeDir = Platform.environment['HOME'] ?? '/tmp';
      final file = File('$homeDir/totalcontrol_fitness.json');

      final data = {
        'date': DateTime.now().toIso8601String().split('T')[0],
        'steps': steps,
        'workout_mins': workoutMins,
        'last_sync': DateTime.now().toIso8601String(),
        'source': 'pacemeter',
      };

      await file.writeAsString(jsonEncode(data));
      debugPrint('[SyncService] Local sync file written');
    } catch (e) {
      debugPrint('[SyncService] Local sync error: $e');
    }
  }

  void dispose() {
    _syncController.close();
  }
}

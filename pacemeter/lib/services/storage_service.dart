// Local storage for activities and settings

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/activity.dart';

class StorageService {
  static final StorageService instance = StorageService._();
  StorageService._();

  Directory? _appDir;
  final List<Activity> _activities = [];
  final Map<String, DailySummary> _dailySummaries = {};

  List<Activity> get activities => List.unmodifiable(_activities);

  Future<void> initialize() async {
    try {
      _appDir = await getApplicationDocumentsDirectory();
      await _loadActivities();
      await _loadDailySummaries();
    } catch (e) {
      debugPrint('[StorageService] Init error: $e');
    }
  }

  File get _activitiesFile => File('${_appDir?.path ?? '/tmp'}/pacemeter_activities.json');
  File get _summariesFile => File('${_appDir?.path ?? '/tmp'}/pacemeter_summaries.json');

  Future<void> _loadActivities() async {
    try {
      if (await _activitiesFile.exists()) {
        final json = jsonDecode(await _activitiesFile.readAsString());
        final list = json['activities'] as List;
        _activities.clear();
        _activities.addAll(list.map((a) => Activity.fromJson(a)));
        debugPrint('[StorageService] Loaded ${_activities.length} activities');
      }
    } catch (e) {
      debugPrint('[StorageService] Load activities error: $e');
    }
  }

  Future<void> _loadDailySummaries() async {
    try {
      if (await _summariesFile.exists()) {
        final json = jsonDecode(await _summariesFile.readAsString());
        final map = json['summaries'] as Map<String, dynamic>;
        _dailySummaries.clear();
        map.forEach((key, value) {
          _dailySummaries[key] = DailySummary.fromJson(value);
        });
        debugPrint('[StorageService] Loaded ${_dailySummaries.length} daily summaries');
      }
    } catch (e) {
      debugPrint('[StorageService] Load summaries error: $e');
    }
  }

  Future<void> saveActivity(Activity activity) async {
    // Remove existing if updating
    _activities.removeWhere((a) => a.id == activity.id);
    _activities.add(activity);

    // Sort by start time (newest first)
    _activities.sort((a, b) => b.startTime.compareTo(a.startTime));

    await _saveActivities();
  }

  Future<void> _saveActivities() async {
    try {
      final json = {
        'activities': _activities.map((a) => a.toJson()).toList(),
        'savedAt': DateTime.now().toIso8601String(),
      };
      await _activitiesFile.writeAsString(jsonEncode(json));
    } catch (e) {
      debugPrint('[StorageService] Save activities error: $e');
    }
  }

  Future<void> saveDailySummary(DailySummary summary) async {
    final key = summary.date.toIso8601String().split('T')[0];
    _dailySummaries[key] = summary;
    await _saveDailySummaries();
  }

  Future<void> _saveDailySummaries() async {
    try {
      final map = <String, dynamic>{};
      _dailySummaries.forEach((key, value) {
        map[key] = value.toJson();
      });
      final json = {
        'summaries': map,
        'savedAt': DateTime.now().toIso8601String(),
      };
      await _summariesFile.writeAsString(jsonEncode(json));
    } catch (e) {
      debugPrint('[StorageService] Save summaries error: $e');
    }
  }

  DailySummary? getSummaryForDate(DateTime date) {
    final key = date.toIso8601String().split('T')[0];
    return _dailySummaries[key];
  }

  DailySummary getTodaySummary() {
    final today = DateTime.now();
    final key = today.toIso8601String().split('T')[0];
    return _dailySummaries[key] ?? DailySummary(date: today);
  }

  List<Activity> getActivitiesForDate(DateTime date) {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    return _activities.where((a) =>
      a.startTime.isAfter(startOfDay) && a.startTime.isBefore(endOfDay)
    ).toList();
  }

  List<Activity> getRecentActivities({int limit = 10}) {
    return _activities.take(limit).toList();
  }

  Future<void> deleteActivity(String id) async {
    _activities.removeWhere((a) => a.id == id);
    await _saveActivities();
  }
}

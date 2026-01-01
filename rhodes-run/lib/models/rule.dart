/// TotalControl Rule Model
/// "NO X UNTIL Y" - Block until condition met
/// "NO X DURING Y" - Block while condition active
/// "ALLOW X DURING Y" - Allow only while condition active

/// Preset categories for quick rule setup
class BlockCategory {
  final String name;
  final String icon;
  final List<String> items;

  const BlockCategory(this.name, this.icon, this.items);

  static const List<BlockCategory> presets = [
    BlockCategory('Social Media', '📱', [
      'Facebook', 'Instagram', 'Twitter', 'X', 'TikTok',
      'Snapchat', 'LinkedIn', 'Pinterest', 'Reddit'
    ]),
    BlockCategory('Streaming', '📺', [
      'Netflix', 'YouTube', 'Hulu', 'Disney+', 'HBO Max',
      'Amazon Prime', 'Twitch', 'Spotify', 'Apple TV'
    ]),
    BlockCategory('Messaging', '💬', [
      'WhatsApp', 'Telegram', 'Discord', 'Slack',
      'Messenger', 'iMessage', 'Signal'
    ]),
    BlockCategory('Gaming', '🎮', [
      'Steam', 'Epic Games', 'Xbox', 'PlayStation',
      'Nintendo', 'Roblox', 'Minecraft'
    ]),
    BlockCategory('News & Media', '📰', [
      'CNN', 'BBC', 'Fox News', 'NYTimes', 'Reddit News',
      'Google News', 'Apple News'
    ]),
    BlockCategory('Dating', '❤️', [
      'Tinder', 'Bumble', 'Hinge', 'OkCupid', 'Match'
    ]),
  ];
}

/// How the rule operates
enum RuleMode {
  until,       // NO X UNTIL Y - blocked until condition met, then unlocked
  during,      // NO X DURING Y - blocked while condition is active
  allowDuring, // ALLOW X DURING Y - allowed only while condition is active
}

enum ConditionType {
  steps,      // UNTIL 10,000 steps
  time,       // UNTIL 5:00 PM (single time)
  timeRange,  // DURING 9:00-17:00 (time range)
  workout,    // UNTIL/DURING 30min workout
  location,   // UNTIL/DURING at gym
  tomorrow,   // UNTIL tomorrow
  password,   // UNTIL password entered
  schedule,   // DURING weekdays / weekends
}

class Location {
  final String name;
  final double latitude;
  final double longitude;
  final int radiusMeters;

  Location({
    required this.name,
    required this.latitude,
    required this.longitude,
    this.radiusMeters = 100,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'lat': latitude,
    'lng': longitude,
    'radius': radiusMeters,
  };

  factory Location.fromJson(Map<String, dynamic> json) => Location(
    name: json['name'],
    latitude: json['lat'],
    longitude: json['lng'],
    radiusMeters: json['radius'] ?? 100,
  );
}

/// Time range for DURING rules (e.g., 9:00-17:00)
class TimeRange {
  final String startTime; // "09:00"
  final String endTime;   // "17:00"

  TimeRange({required this.startTime, required this.endTime});

  bool isActive() {
    final now = DateTime.now();
    final start = _parseTime(startTime);
    final end = _parseTime(endTime);
    final current = now.hour * 60 + now.minute;

    if (end > start) {
      // Normal range: 09:00-17:00
      return current >= start && current < end;
    } else {
      // Overnight range: 22:00-06:00
      return current >= start || current < end;
    }
  }

  int _parseTime(String time) {
    final parts = time.split(':');
    return int.parse(parts[0]) * 60 + (parts.length > 1 ? int.parse(parts[1]) : 0);
  }

  String describe() => '$startTime - $endTime';

  Map<String, dynamic> toJson() => {'start': startTime, 'end': endTime};

  factory TimeRange.fromJson(Map<String, dynamic> json) => TimeRange(
    startTime: json['start'],
    endTime: json['end'],
  );
}

/// Schedule for day-based rules
class Schedule {
  final List<int> days; // 1=Mon, 7=Sun

  Schedule({required this.days});

  bool isActive() => days.contains(DateTime.now().weekday);

  String describe() {
    if (days.length == 5 && !days.contains(6) && !days.contains(7)) {
      return 'weekdays';
    }
    if (days.length == 2 && days.contains(6) && days.contains(7)) {
      return 'weekends';
    }
    const names = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days.map((d) => names[d]).join(', ');
  }

  Map<String, dynamic> toJson() => {'days': days};

  factory Schedule.fromJson(Map<String, dynamic> json) => Schedule(
    days: List<int>.from(json['days'] ?? []),
  );

  static Schedule weekdays() => Schedule(days: [1, 2, 3, 4, 5]);
  static Schedule weekends() => Schedule(days: [6, 7]);
}

class Condition {
  final ConditionType type;
  final int? stepsTarget;
  final String? timeTarget;     // "17:00" - single time for UNTIL
  final TimeRange? timeRange;   // "09:00-17:00" - range for DURING
  final int? workoutMinutes;
  final Location? location;
  final Schedule? schedule;

  Condition({
    required this.type,
    this.stepsTarget,
    this.timeTarget,
    this.timeRange,
    this.workoutMinutes,
    this.location,
    this.schedule,
  });

  String describe() {
    switch (type) {
      case ConditionType.steps:
        return '${stepsTarget?.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')} steps';
      case ConditionType.time:
        return timeTarget ?? 'time';
      case ConditionType.timeRange:
        return timeRange?.describe() ?? 'time range';
      case ConditionType.workout:
        return '${workoutMinutes}min workout';
      case ConditionType.location:
        return 'at ${location?.name ?? "location"}';
      case ConditionType.tomorrow:
        return 'tomorrow';
      case ConditionType.password:
        return 'password';
      case ConditionType.schedule:
        return schedule?.describe() ?? 'schedule';
    }
  }

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{'type': type.name};
    if (stepsTarget != null) json['steps_target'] = stepsTarget;
    if (timeTarget != null) json['time_target'] = timeTarget;
    if (timeRange != null) json['time_range'] = timeRange!.toJson();
    if (workoutMinutes != null) json['workout_minutes'] = workoutMinutes;
    if (location != null) json['location'] = location!.toJson();
    if (schedule != null) json['schedule'] = schedule!.toJson();
    return json;
  }

  factory Condition.fromJson(Map<String, dynamic> json) {
    return Condition(
      type: ConditionType.values.firstWhere((e) => e.name == json['type']),
      stepsTarget: json['steps_target'],
      timeTarget: json['time_target'],
      timeRange: json['time_range'] != null ? TimeRange.fromJson(json['time_range']) : null,
      workoutMinutes: json['workout_minutes'],
      location: json['location'] != null ? Location.fromJson(json['location']) : null,
      schedule: json['schedule'] != null ? Schedule.fromJson(json['schedule']) : null,
    );
  }
}

class Rule {
  final String id;
  final List<String> items;  // Apps/sites affected
  final RuleMode mode;
  final List<Condition> conditions;  // Multiple conditions with AND logic
  final List<String> exceptions;  // UNLESS these items (always allowed)
  final bool enabled;
  final DateTime createdAt;

  Rule({
    required this.id,
    required this.items,
    required this.mode,
    required this.conditions,
    this.exceptions = const [],
    this.enabled = true,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Convenience getter for single condition (backward compatibility)
  Condition get condition => conditions.first;

  /// Human-readable rule description
  String describe() {
    final itemList = items.take(3).join(', ');
    final suffix = items.length > 3 ? ' +${items.length - 3}' : '';
    // Join multiple conditions with " + " for AND logic
    final condDesc = conditions.map((c) => c.describe()).join(' + ');

    String base;
    switch (mode) {
      case RuleMode.until:
        base = 'NO $itemList$suffix UNTIL $condDesc';
      case RuleMode.during:
        // Use BETWEEN for single timeRange condition
        if (conditions.length == 1 && condition.type == ConditionType.timeRange && condition.timeRange != null) {
          base = 'NO $itemList$suffix BETWEEN ${condition.timeRange!.startTime} AND ${condition.timeRange!.endTime}';
        } else {
          base = 'NO $itemList$suffix DURING $condDesc';
        }
      case RuleMode.allowDuring:
        if (conditions.length == 1 && condition.type == ConditionType.timeRange && condition.timeRange != null) {
          base = 'ALLOW $itemList$suffix BETWEEN ${condition.timeRange!.startTime} AND ${condition.timeRange!.endTime}';
        } else {
          base = 'ALLOW $itemList$suffix DURING $condDesc';
        }
    }

    if (exceptions.isNotEmpty) {
      final exceptList = exceptions.take(2).join(', ');
      final exceptSuffix = exceptions.length > 2 ? ' +${exceptions.length - 2}' : '';
      base += ' UNLESS $exceptList$exceptSuffix';
    }

    return base;
  }

  /// Short description for UI
  String get modeLabel {
    switch (mode) {
      case RuleMode.until:
        return 'UNTIL';
      case RuleMode.during:
        return 'BLOCK DURING';
      case RuleMode.allowDuring:
        return 'ONLY DURING';
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'items': items,
    'mode': mode.name,
    'conditions': conditions.map((c) => c.toJson()).toList(),
    'exceptions': exceptions,
    'enabled': enabled,
    'created_at': createdAt.toIso8601String(),
  };

  factory Rule.fromJson(Map<String, dynamic> json) {
    // Support both old 'condition' and new 'conditions' format
    List<Condition> conditionsList;
    if (json['conditions'] != null) {
      conditionsList = (json['conditions'] as List)
          .map((c) => Condition.fromJson(c))
          .toList();
    } else if (json['condition'] != null) {
      // Backward compatibility: single condition
      conditionsList = [Condition.fromJson(json['condition'])];
    } else {
      // Default: tomorrow condition
      conditionsList = [Condition(type: ConditionType.tomorrow)];
    }

    return Rule(
      id: json['id'],
      items: List<String>.from(json['items'] ?? json['blocked_items'] ?? []),
      mode: RuleMode.values.firstWhere(
        (e) => e.name == json['mode'],
        orElse: () => RuleMode.until,
      ),
      conditions: conditionsList,
      exceptions: List<String>.from(json['exceptions'] ?? []),
      enabled: json['enabled'] ?? true,
      createdAt: DateTime.tryParse(json['created_at'] ?? ''),
    );
  }
}

/// Pending change with 1-hour delay for weakening edits
class PendingChange {
  final String id;
  final String ruleId;
  final ChangeType changeType;
  final Rule? originalRule;
  final Rule? newRule;  // null for delete
  final DateTime requestedAt;
  final Duration delay;

  PendingChange({
    required this.id,
    required this.ruleId,
    required this.changeType,
    this.originalRule,
    this.newRule,
    required this.requestedAt,
    this.delay = const Duration(hours: 1),
  });

  DateTime get effectiveAt => requestedAt.add(delay);

  bool get isReady => DateTime.now().isAfter(effectiveAt);

  Duration get timeRemaining {
    final remaining = effectiveAt.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  String get timeRemainingText {
    final r = timeRemaining;
    if (r.inMinutes < 1) return 'Ready';
    if (r.inMinutes < 60) return '${r.inMinutes}m remaining';
    return '${r.inHours}h ${r.inMinutes % 60}m remaining';
  }

  String describe() {
    switch (changeType) {
      case ChangeType.delete:
        return 'Delete rule: ${originalRule?.describe() ?? ruleId}';
      case ChangeType.disable:
        return 'Disable rule: ${originalRule?.describe() ?? ruleId}';
      case ChangeType.weaken:
        return 'Modify rule: ${originalRule?.describe() ?? ruleId}';
      case ChangeType.addException:
        return 'Add exception to: ${originalRule?.describe() ?? ruleId}';
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'rule_id': ruleId,
    'change_type': changeType.name,
    'original_rule': originalRule?.toJson(),
    'new_rule': newRule?.toJson(),
    'requested_at': requestedAt.toIso8601String(),
    'delay_seconds': delay.inSeconds,
  };

  factory PendingChange.fromJson(Map<String, dynamic> json) => PendingChange(
    id: json['id'],
    ruleId: json['rule_id'],
    changeType: ChangeType.values.firstWhere((e) => e.name == json['change_type']),
    originalRule: json['original_rule'] != null ? Rule.fromJson(json['original_rule']) : null,
    newRule: json['new_rule'] != null ? Rule.fromJson(json['new_rule']) : null,
    requestedAt: DateTime.parse(json['requested_at']),
    delay: Duration(seconds: json['delay_seconds'] ?? 3600),
  );
}

enum ChangeType {
  delete,     // Deleting a rule
  disable,    // Disabling a rule
  weaken,     // Reducing protection (lower targets, etc)
  addException, // Adding an exception
}

/// Check if a change weakens protection (requires delay)
bool isWeakeningChange(Rule? original, Rule? modified) {
  if (original == null) return false;  // New rule = strengthening
  if (modified == null) return true;   // Delete = weakening

  // Disabling = weakening
  if (original.enabled && !modified.enabled) return true;

  // Adding exceptions = weakening
  if (modified.exceptions.length > original.exceptions.length) return true;

  // Changing from until to allowDuring = weakening
  if (original.mode == RuleMode.until && modified.mode == RuleMode.allowDuring) return true;

  // Reducing targets = weakening
  for (int i = 0; i < original.conditions.length && i < modified.conditions.length; i++) {
    final origCond = original.conditions[i];
    final modCond = modified.conditions[i];

    // Lower step target
    if (origCond.stepsTarget != null && modCond.stepsTarget != null) {
      if (modCond.stepsTarget! < origCond.stepsTarget!) return true;
    }
    // Lower workout minutes
    if (origCond.workoutMinutes != null && modCond.workoutMinutes != null) {
      if (modCond.workoutMinutes! < origCond.workoutMinutes!) return true;
    }
    // Earlier time target
    if (origCond.timeTarget != null && modCond.timeTarget != null) {
      if (modCond.timeTarget!.compareTo(origCond.timeTarget!) < 0) return true;
    }
  }

  // Fewer conditions = weakening (less to satisfy)
  if (modified.conditions.length < original.conditions.length) return true;

  return false;
}

class Progress {
  int stepsToday;
  int workoutMinutesToday;
  Location? currentLocation;
  bool workoutActive;  // Currently working out

  Progress({
    this.stepsToday = 0,
    this.workoutMinutesToday = 0,
    this.currentLocation,
    this.workoutActive = false,
  });

  /// Check if a condition is currently met/active
  /// Returns (conditionMet, statusText)
  (bool met, String status) checkCondition(Condition condition) {
    switch (condition.type) {
      case ConditionType.steps:
        final target = condition.stepsTarget ?? 10000;
        final met = stepsToday >= target;
        final pct = (stepsToday / target * 100).clamp(0, 100).toInt();
        return (met, '$stepsToday/$target ($pct%)');

      case ConditionType.time:
        final parts = (condition.timeTarget ?? '17:00').split(':');
        final targetHour = int.parse(parts[0]);
        final targetMin = parts.length > 1 ? int.parse(parts[1]) : 0;
        final now = DateTime.now();
        final target = DateTime(now.year, now.month, now.day, targetHour, targetMin);

        if (now.isAfter(target)) {
          return (true, 'Time reached');
        }
        final diff = target.difference(now);
        if (diff.inMinutes > 60) {
          return (false, '${diff.inHours}h ${diff.inMinutes % 60}m left');
        }
        return (false, '${diff.inMinutes}m left');

      case ConditionType.timeRange:
        final active = condition.timeRange?.isActive() ?? false;
        final desc = condition.timeRange?.describe() ?? '';
        return (active, active ? 'In range ($desc)' : 'Outside range ($desc)');

      case ConditionType.workout:
        final target = condition.workoutMinutes ?? 30;
        final met = workoutMinutesToday >= target;
        return (met, '$workoutMinutesToday/${target}min');

      case ConditionType.location:
        if (currentLocation == null || condition.location == null) {
          return (false, 'Location unknown');
        }
        // Simple distance check
        final dx = currentLocation!.latitude - condition.location!.latitude;
        final dy = currentLocation!.longitude - condition.location!.longitude;
        final distMeters = (dx * dx + dy * dy) * 111000; // rough
        final met = distMeters <= condition.location!.radiusMeters;
        return (met, met ? 'At ${condition.location!.name}' : 'Not at ${condition.location!.name}');

      case ConditionType.tomorrow:
        return (false, 'Blocked until tomorrow');

      case ConditionType.password:
        return (false, 'Enter password');

      case ConditionType.schedule:
        final active = condition.schedule?.isActive() ?? false;
        final desc = condition.schedule?.describe() ?? '';
        return (active, active ? 'Active ($desc)' : 'Inactive ($desc)');
    }
  }

  /// Check all conditions and return (allMet, statusList)
  (bool allMet, List<String> statuses) checkAllConditions(Rule rule) {
    final results = rule.conditions.map((c) => checkCondition(c)).toList();
    final allMet = results.every((r) => r.$1);
    final statuses = results.map((r) => r.$2).toList();
    return (allMet, statuses);
  }

  /// Determine if a rule's items are currently blocked
  bool isBlocked(Rule rule) {
    final (allConditionsMet, _) = checkAllConditions(rule);

    switch (rule.mode) {
      case RuleMode.until:
        // Blocked until ALL conditions met (AND logic)
        return !allConditionsMet;
      case RuleMode.during:
        // Blocked while ALL conditions are active
        return allConditionsMet;
      case RuleMode.allowDuring:
        // Blocked unless ALL conditions are active
        return !allConditionsMet;
    }
  }

  /// Get status text with blocking state
  (bool blocked, String status) getRuleStatus(Rule rule) {
    final (allMet, statuses) = checkAllConditions(rule);
    final blocked = isBlocked(rule);
    final condStatus = statuses.join(' + ');

    String status;
    switch (rule.mode) {
      case RuleMode.until:
        status = blocked ? 'Blocked - $condStatus' : 'Unlocked';
      case RuleMode.during:
        status = blocked ? 'Blocked during $condStatus' : 'Allowed';
      case RuleMode.allowDuring:
        final desc = rule.conditions.map((c) => c.describe()).join(' + ');
        status = blocked ? 'Only during $desc' : 'Allowed now';
    }
    return (blocked, status);
  }
}

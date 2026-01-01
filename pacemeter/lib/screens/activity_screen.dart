import 'dart:async';
import 'package:flutter/material.dart';
import '../services/location_service.dart';
import '../services/health_service.dart';
import '../services/sync_service.dart';
import '../services/storage_service.dart';
import '../models/activity.dart';

class ActivityScreen extends StatefulWidget {
  final Activity activity;

  const ActivityScreen({super.key, required this.activity});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  final _location = LocationService.instance;
  final _health = HealthService.instance;
  final _sync = SyncService.instance;
  final _storage = StorageService.instance;

  late Activity _activity;
  Timer? _timer;
  Duration _elapsed = Duration.zero;
  bool _isPaused = false;
  StreamSubscription? _locationSub;
  StreamSubscription? _activitySub;

  @override
  void initState() {
    super.initState();
    _activity = widget.activity;
    _startTimer();
    _subscribeToUpdates();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isPaused) {
        setState(() {
          _elapsed = DateTime.now().difference(_activity.startTime);
        });
      }
    });
  }

  void _subscribeToUpdates() {
    _activitySub = _location.activityStream.listen((activity) {
      setState(() {
        _activity = activity;
      });
    });

    _locationSub = _location.locationStream.listen((point) {
      // Could update map here
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _locationSub?.cancel();
    _activitySub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text(
                    _activity.type.icon,
                    style: const TextStyle(fontSize: 32),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _activity.type.displayName,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  if (_isPaused)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'PAUSED',
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Timer
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Duration
                    Text(
                      _formatDuration(_elapsed),
                      style: const TextStyle(
                        fontSize: 64,
                        fontWeight: FontWeight.w300,
                        fontFamily: 'monospace',
                        letterSpacing: 4,
                      ),
                    ),
                    const SizedBox(height: 40),

                    // Stats row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _StatColumn(
                          label: 'DISTANCE',
                          value: _formatDistance(_activity.distanceMeters),
                          unit: 'km',
                        ),
                        _StatColumn(
                          label: 'PACE',
                          value: _formatPace(_activity.paceMinPerKm),
                          unit: '/km',
                        ),
                        _StatColumn(
                          label: 'POINTS',
                          value: '${_activity.route.length}',
                          unit: 'GPS',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Map placeholder
            Container(
              height: 150,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.map, size: 48, color: Colors.white30),
                    const SizedBox(height: 8),
                    Text(
                      '${_activity.route.length} GPS points recorded',
                      style: TextStyle(color: Colors.white54),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Controls
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Pause/Resume
                  _ControlButton(
                    icon: _isPaused ? Icons.play_arrow : Icons.pause,
                    label: _isPaused ? 'Resume' : 'Pause',
                    onTap: _togglePause,
                    color: Colors.white,
                    backgroundColor: Colors.white24,
                  ),

                  // Stop
                  _ControlButton(
                    icon: Icons.stop,
                    label: 'Finish',
                    onTap: _finishActivity,
                    color: Colors.black,
                    backgroundColor: theme.colorScheme.primary,
                    size: 80,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatDistance(double meters) {
    return (meters / 1000).toStringAsFixed(2);
  }

  String _formatPace(double minPerKm) {
    if (minPerKm == 0 || minPerKm.isInfinite || minPerKm.isNaN) {
      return '--:--';
    }
    final mins = minPerKm.floor();
    final secs = ((minPerKm - mins) * 60).round();
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  void _togglePause() {
    setState(() {
      _isPaused = !_isPaused;
      if (_isPaused) {
        _location.pauseTracking();
      } else {
        _location.resumeTracking();
      }
    });
  }

  Future<void> _finishActivity() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Finish Activity?'),
        content: Text(
          'Duration: ${_formatDuration(_elapsed)}\n'
          'Distance: ${_formatDistance(_activity.distanceMeters)} km\n'
          'GPS Points: ${_activity.route.length}'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Continue'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Finish'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final finalActivity = await _location.stopActivity();

      // Save locally
      await _storage.saveActivity(finalActivity);

      // Sync to cloud
      await _sync.syncActivity(finalActivity);

      // Update steps if walking/running
      if (finalActivity.type == ActivityType.walk ||
          finalActivity.type == ActivityType.run) {
        // Estimate steps: ~1300 steps per km walking, ~1000 running
        final stepsPerKm = finalActivity.type == ActivityType.walk ? 1300 : 1000;
        final estimatedSteps = (finalActivity.distanceKm * stepsPerKm).round();
        _health.addSteps(estimatedSteps);
        await _sync.syncSteps(_health.stepsToday);
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Activity saved!')),
      );

      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }
}

class _StatColumn extends StatelessWidget {
  final String label;
  final String value;
  final String unit;

  const _StatColumn({
    required this.label,
    required this.value,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.white54,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 4, left: 4),
              child: Text(
                unit,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white54,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
  final Color backgroundColor;
  final double size;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.color,
    required this.backgroundColor,
    this.size = 64,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: backgroundColor,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(icon, color: color, size: size * 0.5),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.white54,
          ),
        ),
      ],
    );
  }
}

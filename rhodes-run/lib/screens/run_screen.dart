import 'dart:async';
import 'package:flutter/material.dart';
import '../services/location_service.dart';
import '../services/health_service.dart';
import '../models/activity.dart' as models;

/// Quick GPS run screen for Rhodes Run
class RunScreen extends StatefulWidget {
  const RunScreen({super.key});

  @override
  State<RunScreen> createState() => _RunScreenState();
}

class _RunScreenState extends State<RunScreen> {
  final _location = LocationService.instance;
  final _health = HealthService.instance;

  bool _isTracking = false;
  models.Activity? _currentActivity;
  Timer? _timer;
  Duration _elapsed = Duration.zero;
  StreamSubscription? _activitySub;

  @override
  void initState() {
    super.initState();
    _location.initialize();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _activitySub?.cancel();
    super.dispose();
  }

  Future<void> _startRun() async {
    final activity = await _location.startActivity(models.ActivityType.run);
    setState(() {
      _isTracking = true;
      _currentActivity = activity;
      _elapsed = Duration.zero;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        _elapsed = DateTime.now().difference(_currentActivity!.startTime);
      });
    });

    _activitySub = _location.activityStream.listen((updated) {
      setState(() => _currentActivity = updated);
    });
  }

  Future<void> _stopRun() async {
    _timer?.cancel();
    _activitySub?.cancel();
    await _location.stopActivity();

    setState(() {
      _isTracking = false;
      _currentActivity = null;
    });
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final distance = _location.totalDistance;
    final pace = _location.currentPace;
    final speed = _location.currentSpeed;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // Header
              Text(
                'RUN',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                  letterSpacing: 4,
                ),
              ),
              const SizedBox(height: 40),

              // Timer
              Text(
                _formatDuration(_elapsed),
                style: TextStyle(
                  fontSize: 72,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                  fontFamily: 'Courier',
                ),
              ),
              const SizedBox(height: 30),

              // Stats row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _StatBox(
                    label: 'DISTANCE',
                    value: '${(distance / 1000).toStringAsFixed(2)} km',
                  ),
                  _StatBox(
                    label: 'PACE',
                    value: pace > 0 ? '${pace.toStringAsFixed(1)} min/km' : '--',
                  ),
                  _StatBox(
                    label: 'SPEED',
                    value: '${speed.toStringAsFixed(1)} km/h',
                  ),
                ],
              ),

              const Spacer(),

              // Start/Stop button
              GestureDetector(
                onTap: _isTracking ? _stopRun : _startRun,
                child: Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isTracking ? Colors.red : Theme.of(context).colorScheme.primary,
                    boxShadow: [
                      BoxShadow(
                        color: (_isTracking ? Colors.red : Theme.of(context).colorScheme.primary).withAlpha(100),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Icon(
                      _isTracking ? Icons.stop : Icons.play_arrow,
                      size: 80,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                _isTracking ? 'TAP TO STOP' : 'TAP TO START',
                style: const TextStyle(
                  color: Colors.white54,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String label;
  final String value;

  const _StatBox({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 12,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

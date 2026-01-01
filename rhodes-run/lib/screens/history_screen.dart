import 'package:flutter/material.dart';
import '../services/storage_service.dart';
import '../models/activity.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _storage = StorageService.instance;

  @override
  Widget build(BuildContext context) {
    final activities = _storage.activities;

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          floating: true,
          title: const Text('Activity History'),
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        ),
        if (activities.isEmpty)
          SliverFillRemaining(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.directions_run,
                    size: 64,
                    color: Colors.white24,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No activities yet',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.white54,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Start a walk or run to track your progress',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white38,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final activity = activities[index];
                  return _ActivityCard(
                    activity: activity,
                    onDelete: () => _deleteActivity(activity.id),
                  );
                },
                childCount: activities.length,
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _deleteActivity(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Activity?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _storage.deleteActivity(id);
      setState(() {});
    }
  }
}

class _ActivityCard extends StatelessWidget {
  final Activity activity;
  final VoidCallback onDelete;

  const _ActivityCard({
    required this.activity,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _showDetails(context),
        onLongPress: onDelete,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Activity icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    activity.type.icon,
                    style: const TextStyle(fontSize: 24),
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      activity.type.displayName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatDate(activity.startTime),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white54,
                      ),
                    ),
                  ],
                ),
              ),

              // Stats
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatDistance(activity.distanceMeters),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    _formatDuration(activity.duration),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white54,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final hour = date.hour > 12 ? date.hour - 12 : date.hour;
    final ampm = date.hour >= 12 ? 'PM' : 'AM';
    return '${months[date.month - 1]} ${date.day}, ${hour == 0 ? 12 : hour}:${date.minute.toString().padLeft(2, '0')} $ampm';
  }

  String _formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.round()} m';
    }
    return '${(meters / 1000).toStringAsFixed(2)} km';
  }

  String _formatDuration(Duration duration) {
    if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes.remainder(60)}m';
    }
    return '${duration.inMinutes}m ${duration.inSeconds.remainder(60)}s';
  }

  void _showDetails(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  activity.type.icon,
                  style: const TextStyle(fontSize: 32),
                ),
                const SizedBox(width: 12),
                Text(
                  activity.type.displayName,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ],
            ),
            const SizedBox(height: 24),
            _DetailRow('Date', _formatDate(activity.startTime)),
            _DetailRow('Duration', _formatDuration(activity.duration)),
            _DetailRow('Distance', _formatDistance(activity.distanceMeters)),
            _DetailRow('Avg Speed', '${activity.avgSpeedKmh.toStringAsFixed(1)} km/h'),
            _DetailRow('GPS Points', '${activity.route.length}'),
            if (activity.steps > 0)
              _DetailRow('Steps', '${activity.steps}'),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  onDelete();
                },
                icon: const Icon(Icons.delete, color: Colors.red),
                label: const Text('Delete', style: TextStyle(color: Colors.red)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.white54),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../services/health_service.dart';
import '../services/location_service.dart';
import '../services/sync_service.dart';
import '../models/activity.dart';
import 'activity_screen.dart';
import 'history_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final _health = HealthService.instance;
  final _location = LocationService.instance;
  final _sync = SyncService.instance;

  late AnimationController _pulseController;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _initServices();
  }

  Future<void> _initServices() async {
    await _health.requestAuthorization();
    await _health.fetchStepsToday();
    setState(() {});
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _selectedIndex,
          children: [
            _buildDashboard(),
            const HistoryScreen(),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Today',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'History',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showActivityPicker,
        icon: const Icon(Icons.add),
        label: const Text('Start Activity'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.black,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildDashboard() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 24),
          _buildStepsCard(),
          const SizedBox(height: 16),
          _buildQuickStats(),
          const SizedBox(height: 16),
          _buildActivityButtons(),
          const SizedBox(height: 80), // Space for FAB
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pacemeter',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            Text(
              _getDateString(),
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Colors.white54,
              ),
            ),
          ],
        ),
        IconButton(
          onPressed: _syncData,
          icon: Icon(
            _sync.isConnected ? Icons.cloud_done : Icons.cloud_off,
            color: _sync.isConnected ? Colors.green : Colors.grey,
          ),
          tooltip: 'Sync',
        ),
      ],
    );
  }

  Widget _buildStepsCard() {
    final progress = _health.progress.clamp(0.0, 1.0);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Circular progress
            SizedBox(
              width: 200,
              height: 200,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Background circle
                  SizedBox(
                    width: 180,
                    height: 180,
                    child: CircularProgressIndicator(
                      value: 1,
                      strokeWidth: 12,
                      color: Colors.white10,
                    ),
                  ),
                  // Progress
                  SizedBox(
                    width: 180,
                    height: 180,
                    child: AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        return CircularProgressIndicator(
                          value: progress,
                          strokeWidth: 12,
                          strokeCap: StrokeCap.round,
                          color: Color.lerp(
                            Theme.of(context).colorScheme.primary,
                            Theme.of(context).colorScheme.secondary,
                            _pulseController.value,
                          ),
                        );
                      },
                    ),
                  ),
                  // Step count
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${_health.stepsToday}',
                        style: const TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'of ${_health.stepsGoal} steps',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white54,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Add steps button
            OutlinedButton.icon(
              onPressed: _showAddStepsDialog,
              icon: const Icon(Icons.add),
              label: const Text('Add Steps Manually'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickStats() {
    final distanceKm = _health.distanceToday / 1000;
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.local_fire_department,
            value: '${_health.caloriesToday.toInt()}',
            label: 'Calories',
            color: Colors.orange,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            icon: Icons.straighten,
            value: '${distanceKm.toStringAsFixed(1)} km',
            label: 'Distance',
            color: Colors.blue,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            icon: Icons.timer,
            value: '${_health.activeMinutesToday} min',
            label: 'Active',
            color: Colors.purple,
          ),
        ),
      ],
    );
  }

  Widget _buildActivityButtons() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Start',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: Colors.white70,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _ActivityButton(
                type: ActivityType.walk,
                onTap: () => _startActivity(ActivityType.walk),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ActivityButton(
                type: ActivityType.run,
                onTap: () => _startActivity(ActivityType.run),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _ActivityButton(
                type: ActivityType.bike,
                onTap: () => _startActivity(ActivityType.bike),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ActivityButton(
                type: ActivityType.hike,
                onTap: () => _startActivity(ActivityType.hike),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _getDateString() {
    final now = DateTime.now();
    final weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${weekdays[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}';
  }

  void _showActivityPicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Start Activity',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            ...ActivityType.values.map((type) => ListTile(
              leading: Text(type.icon, style: const TextStyle(fontSize: 28)),
              title: Text(type.displayName),
              onTap: () {
                Navigator.pop(context);
                _startActivity(type);
              },
            )),
          ],
        ),
      ),
    );
  }

  void _startActivity(ActivityType type) async {
    final activity = await _location.startActivity(type);
    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ActivityScreen(activity: activity),
      ),
    );
  }

  void _showAddStepsDialog() {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Steps'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Number of steps',
            hintText: 'e.g., 1000',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final steps = int.tryParse(controller.text) ?? 0;
              if (steps > 0) {
                _health.addSteps(steps);
                setState(() {});
                _syncData();
              }
              Navigator.pop(context);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _syncData() async {
    await _sync.syncSteps(_health.stepsToday);
    await _sync.writeLocalSync(_health.stepsToday, 0);
    setState(() {});

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_sync.isConnected ? 'Synced!' : 'Sync failed'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.white54,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityButton extends StatelessWidget {
  final ActivityType type;
  final VoidCallback onTap;

  const _ActivityButton({
    required this.type,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Text(type.icon, style: const TextStyle(fontSize: 32)),
              const SizedBox(height: 8),
              Text(
                type.displayName,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
